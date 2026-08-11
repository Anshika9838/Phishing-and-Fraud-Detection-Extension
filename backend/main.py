from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Any
import logging
import uvicorn
import json
import os
import asyncio
from urllib.parse import urlparse
from dotenv import load_dotenv

try:
    from llm_analyzer import analyze_scan_report
    from threat_feeds import run_all_reputation_checks
    from infra_analyzer import run_infra_checks
except ImportError:  # Allows importing as backend.main during tests/tools.
    from .llm_analyzer import analyze_scan_report
    from .threat_feeds import run_all_reputation_checks
    from .infra_analyzer import run_infra_checks

# Load environment variables from .env file
load_dotenv()
# Initialize the FastAPI app
app = FastAPI(
    title="Theft Alert API",
    description="Backend server for Team Paradox Phishing and Fraud Detection",
    version="1.0.0"
)

# ===================================================
# Logging Configuration
# ===================================================
# Create a logger for saving scan reports to a file.
# This will create a 'scan_reports.log' file in your backend directory.
report_logger = logging.getLogger("scan_reports")
report_logger = logging.getLogger("scan_reports")
report_logger.setLevel(logging.INFO)
report_logger.propagate = False  # stop it from also bubbling to the root logger

if not report_logger.handlers:
    file_handler = logging.FileHandler("scan_reports.log")
    file_handler.setLevel(logging.INFO)
    formatter = logging.Formatter('%(asctime)s - %(message)s')
    file_handler.setFormatter(formatter)
    report_logger.addHandler(file_handler)

manual_report_logger = logging.getLogger("manual_reports")
manual_report_logger.setLevel(logging.INFO)
manual_report_logger.propagate = False

if not manual_report_logger.handlers:
    manual_file_handler = logging.FileHandler("manual_reports.log")
    manual_file_handler.setLevel(logging.INFO)
    manual_formatter = logging.Formatter('%(asctime)s - %(message)s')
    manual_file_handler.setFormatter(manual_formatter)
    manual_report_logger.addHandler(manual_file_handler)

analysis_results_logger = logging.getLogger("analysis_results")
analysis_results_logger.setLevel(logging.INFO)
analysis_results_logger.propagate = False

if not analysis_results_logger.handlers:
    analysis_results_handler = logging.FileHandler("analysis_results.log")
    analysis_results_handler.setLevel(logging.INFO)
    analysis_results_formatter = logging.Formatter('%(asctime)s - %(message)s')
    analysis_results_handler.setFormatter(analysis_results_formatter)
    analysis_results_logger.addHandler(analysis_results_handler)


# ===================================================
# Pydantic Models
# ===================================================
class UrlCheckRequest(BaseModel):
    url: str
# ===================================================
# CORS Configuration
# ===================================================
# During development, "*" allows requests from any origin.
# For production, replace "*" with your specific domains and Chrome Extension ID.
origins = [
    "*", 
    # "http://localhost",
    # "http://localhost:3000",
    # "chrome-extension://YOUR_EXTENSION_ID_HERE"
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ===================================================
# WebSocket Connection Manager
# ===================================================
class ConnectionManager:
    def __init__(self):
        # Store active connections
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def send_personal_message(self, message: str, websocket: WebSocket):
        await websocket.send_text(message)

    async def broadcast(self, message: str):
        for connection in self.active_connections:
            await connection.send_text(message)

manager = ConnectionManager()

# ===================================================
# REST API Routes
# ===================================================
@app.get("/")
async def root():
    return {"status": "online", "service": "Theft Alert API"}

@app.post("/api/report")
async def report_url(url_data: dict):
    """
    Receives detailed website data from the extension, logs it, analyzes the URL,
    and broadcasts the analysis result to WebSocket clients.
    """
    url_to_check = url_data.get("url")
    domain_to_check = urlparse(url_to_check).netloc if url_to_check else "N/A"

    # 1. Debugger anchor to print the domain
    print(f"--- [DEBUG ANCHOR] --- Processing request for domain: {domain_to_check} ---")

    # Log the full data payload to scan_reports.log for later analysis
    report_logger.info(json.dumps(url_data, indent=2))

    # Run all reputation and infrastructure checks concurrently
    reputation_task = run_all_reputation_checks(url_to_check)
    infra_task = run_infra_checks(url_to_check, url_data)
    reputation_results, infra_results = await asyncio.gather(reputation_task, infra_task)

    all_checks = reputation_results.get("checks", []) + infra_results.get("checks", [])

    # Find the Google Safe Browsing result for the LLM and logging
    google_result = next(
        (check for check in all_checks if check.get("source") == "Google Safe Browsing"),
        {
            "score": 0.5, "risk_score": 50, "threat_type": "UNKNOWN", "verdict": "UNKNOWN",
            "source": "Google Safe Browsing", "details": "Check did not run or failed."
        }
    )

    # 2. Show the response from Google Safe Search API
    print(f"[DEBUG] Google Safe Browsing response for {domain_to_check}: {google_result}")

    llm_scan_report = {
        **url_data,
        "reputation_checks": all_checks,
    }

    analysis_bundle = analyze_scan_report(llm_scan_report, google_result, use_gemini=True)
    final_analysis = analysis_bundle["analysis"]
    raw_gemini_response = analysis_bundle.get("raw_gemini_response")

    # 3. Print the report of analysis from Gemini
    if raw_gemini_response:
        print(f"[DEBUG] Gemini analysis report for {domain_to_check}:")
        print(json.dumps(raw_gemini_response, indent=2))

    # 4. Create a separate text file and save the results
    analysis_log_entry = {
        "url": url_to_check,
        "domain": domain_to_check,
        "all_scan_results": all_checks,
        "google_safe_browsing_response": google_result,
        "gemini_response": raw_gemini_response,
        "final_analysis_summary": {
            "risk_score": final_analysis.get("risk_score"),
            "threat_type": final_analysis.get("threat_type"),
            "brief_reason": final_analysis.get("brief_reason"),
            "analysis_source": final_analysis.get("analysis_source"),
        }
    }
    analysis_results_logger.info(json.dumps(analysis_log_entry, indent=2))

    final_analysis["reputation_checks"] = all_checks
    final_analysis["report_type"] = url_data.get("reportType", "full_page_scan")
    final_analysis["scan_trigger"] = url_data.get("scanTrigger")
    final_analysis["page_url"] = url_data.get("sourcePageUrl") or url_to_check

    # Broadcast the analysis result to all connected clients (the extension)
    await manager.broadcast(json.dumps(final_analysis))

    return {
        "message": "Report received, logged, analyzed, and broadcasted.",
        "domain": url_data.get("domain"),
        "analysis": final_analysis,
    }

@app.post("/api/check_url")
async def check_url_only(request: UrlCheckRequest):
    """
    Receives a single URL (e.g., from a mobile app), analyzes it,
    and returns the analysis result directly.
    """
    # For a quick check, we can just run the reputation checks
    reputation_results = await run_all_reputation_checks(request.url)
    
    # For now, just return the raw checks. A more advanced version could run a
    # lightweight scoring model here.
    analysis_result = reputation_results

    return analysis_result

@app.post("/api/manual_report")
async def manual_report(request: UrlCheckRequest):
    """
    Receives a manually reported URL from the extension popup and logs it.
    """
    manual_report_logger.info(f"Manually reported URL: {request.url}")
    return {"message": "Site reported successfully. Thank you for your contribution!"}

# ===================================================
# WebSocket Route
# ===================================================
@app.websocket("/ws/{client_id}")
async def websocket_endpoint(websocket: WebSocket, client_id: str):
    await manager.connect(websocket)
    try:
        while True:
            # Wait for messages from the connected client
            data = await websocket.receive_text()
            
            # Send an acknowledgment back to the specific client
            await manager.send_personal_message(f"Server received: {data}", websocket)
            
            # Example of broadcasting to all connected clients (e.g., global threat alert)
            # await manager.broadcast(f"Alert from {client_id}: {data}")
            
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        print(f"Client #{client_id} disconnected")

if __name__ == "__main__":
    # Run the server. 
    # 'main:app' refers to the file 'main.py' and the 'app' instance inside it.
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)