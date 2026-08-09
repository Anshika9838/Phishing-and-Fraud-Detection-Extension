from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List
import logging
import uvicorn
import json
import os
import requests
from dotenv import load_dotenv

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
report_logger.setLevel(logging.INFO)

# Create a file handler
file_handler = logging.FileHandler("scan_reports.log")
file_handler.setLevel(logging.INFO)

# Create a formatter and add it to the handler
formatter = logging.Formatter('%(asctime)s - %(message)s')
file_handler.setFormatter(formatter)

report_logger.addHandler(file_handler)

# Create a logger for manually reported sites
manual_report_logger = logging.getLogger("manual_reports")
manual_report_logger.setLevel(logging.INFO)
manual_file_handler = logging.FileHandler("manual_reports.log")
manual_file_handler.setLevel(logging.INFO)
manual_formatter = logging.Formatter('%(asctime)s - %(message)s')
manual_file_handler.setFormatter(manual_formatter)
manual_report_logger.addHandler(manual_file_handler)

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

async def check_google_safe_browsing(url: str):
    """
    Checks a URL against the Google Safe Browsing API.
    """
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        print("Warning: GOOGLE_API_KEY not found. Skipping safe browsing check.")
        return {
            "score": 0.5,
            "threat_type": "UNKNOWN",
            "description": "Google Safe Browsing check could not be performed. API key is missing."
        }

    api_url = f"https://safebrowsing.googleapis.com/v4/threatMatches:find?key={api_key}"
    payload = {
        "client": {"clientId": "team-paradox-extension", "clientVersion": "1.0.0"},
        "threatInfo": {
            "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
            "platformTypes": ["ANY_PLATFORM"],
            "threatEntryTypes": ["URL"],
            "threatEntries": [{"url": url}]
        }
    }

    try:
        response = requests.post(api_url, json=payload)
        response.raise_for_status()
        data = response.json()

        if "matches" in data:
            threat_type = data["matches"][0]["threatType"]
            return {
                "score": 0.9,  # High score for detected threats
                "threat_type": threat_type,
                "description": f"**Warning!** Google has identified this site as a potential threat for **{threat_type.replace('_', ' ').title()}**."
            }
        else:
            return {
                "score": 0.1,  # Low score for safe sites
                "threat_type": "SAFE",
                "description": "This site is not known to host malicious content according to Google Safe Browsing."
            }
    except requests.exceptions.RequestException as e:
        print(f"Error calling Google Safe Browsing API: {e}")
        return {
            "score": 0.5,
            "threat_type": "API_ERROR",
            "description": f"Could not verify the site. An error occurred while contacting Google Safe Browsing: {e}"
        }

@app.post("/api/report")
async def report_url(url_data: dict):
    """
    Receives detailed website data from the extension, logs it, analyzes the URL,
    and broadcasts the analysis result to WebSocket clients.
    """
    # DEBUG: Log that a request has been received, including the trigger and frame type.
    print(f"[DEBUG] Backend: Received POST at /api/report. Trigger: {url_data.get('scanTrigger')}, isTopFrame: {url_data.get('isTopFrame')}")

    url_to_check = url_data.get("url")

    # Log the full data payload to scan_reports.log for later analysis
    report_logger.info(json.dumps(url_data, indent=2))

    # Perform analysis
    analysis_result = await check_google_safe_browsing(url_to_check)

    # Broadcast the analysis result to all connected clients (the extension)
    await manager.broadcast(json.dumps(analysis_result))

    return {"message": "Report received, logged, and analysis broadcasted.", "domain": url_data.get("domain")}

@app.post("/api/check_url")
async def check_url_only(request: UrlCheckRequest):
    """
    Receives a single URL (e.g., from a mobile app), analyzes it,
    and returns the analysis result directly.
    """
    analysis_result = await check_google_safe_browsing(request.url)
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