from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List
import logging
import uvicorn
import json
import os
import requests
import dns.resolver
import whois
from urllib.parse import urlparse
from dotenv import load_dotenv

try:
    from llm_analyzer import analyze_scan_report
except ImportError:  # Allows importing as backend.main during tests/tools.
    from .llm_analyzer import analyze_scan_report

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

async def check_openphish(url: str):
    """Checks a URL against the OpenPhish feed."""
    try:
        # OpenPhish provides a simple text feed. We'll check if the domain is in it.
        domain = urlparse(url).netloc
        openphish_url = "https://openphish.com/feed.txt"
        response = requests.get(openphish_url, timeout=5)
        response.raise_for_status()
        if domain in response.text:
            return {
                "score": 0.9,
                "source": "OpenPhish",
                "details": "Domain found in the OpenPhish intelligence feed."
            }
        return {
            "score": 0.1,
            "source": "OpenPhish",
            "details": "Domain not listed in the OpenPhish feed."
        }
    except requests.RequestException as e:
        return {
            "score": 0.5,
            "source": "OpenPhish",
            "details": f"Could not check OpenPhish: {e}"
        }

async def check_spamhaus(url: str):
    """Checks the domain's IP against Spamhaus DNSBLs."""
    try:
        domain = urlparse(url).netloc
        ip = dns.resolver.resolve(domain, 'A')[0].to_text()
        reversed_ip = '.'.join(reversed(ip.split('.')))
        
        # We will check against two common Spamhaus lists
        zen_query = f"{reversed_ip}.zen.spamhaus.org"
        
        try:
            dns.resolver.resolve(zen_query, 'A')
            return {
                "score": 0.8,
                "source": "Spamhaus",
                "details": f"IP address ({ip}) is listed on the Spamhaus Zen blocklist."
            }
        except dns.resolver.NXDOMAIN:
            return {
                "score": 0.1,
                "source": "Spamhaus",
                "details": "IP address is not on the Spamhaus Zen blocklist."
            }
    except Exception as e:
        return {
            "score": 0.5,
            "source": "Spamhaus",
            "details": f"Could not perform Spamhaus check: {e}"
        }

async def get_domain_details(url: str):
    """Fetches WHOIS and Qualys SSL Labs details for the domain."""
    domain = urlparse(url).netloc
    details = {
        "whois": "Could not fetch WHOIS data.",
        "ssl_labs": "Could not fetch SSL Labs data."
    }
    
    # WHOIS lookup
    try:
        w = whois.whois(domain)
        if w.creation_date:
            # Handle cases where creation_date can be a list
            creation_date_val = w.creation_date[0] if isinstance(w.creation_date, list) else w.creation_date
            details["whois"] = f"Registered on: {creation_date_val.strftime('%Y-%m-%d')}. Registrar: {w.registrar}."
        else:
            details["whois"] = "Domain registration date not found."
    except Exception as e:
        details["whois"] = f"WHOIS lookup failed: {e}"

    # Qualys SSL Labs lookup for cached results
    try:
        qualys_api_url = "https://api.ssllabs.com/api/v3/analyze"
        # Use fromCache to get a recent report without waiting for a new scan.
        params = {'host': domain, 'fromCache': 'on', 'maxAge': 24}
        # Increased timeout for potentially slow API responses
        response = requests.get(qualys_api_url, params=params, timeout=10)
        response.raise_for_status()
        qualys_data = response.json()
        
        if qualys_data.get('status') == 'READY' and qualys_data.get('endpoints'):
            grade = qualys_data['endpoints'][0].get('grade', 'N/A')
            details["ssl_labs"] = f"SSL Labs Grade: **{grade}**. (Based on a cached scan from the last 24 hours)"
        elif qualys_data.get('status') == 'IN_PROGRESS':
            details["ssl_labs"] = "No cached SSL Labs report available. A new scan has been initiated."
        else:
            # Handle errors or other statuses from Qualys
            error_message = qualys_data.get('errors', [{}])[0].get('message', 'Unknown status')
            details["ssl_labs"] = f"SSL Labs check status: {qualys_data.get('status', 'Unknown')}. {error_message}"

    except requests.RequestException as e:
        details["ssl_labs"] = f"Qualys SSL Labs lookup failed: {e}"
        
    return {
        "score": 0.3, # Neutral score, as this is informational
        "source": "Domain Details",
        "details": f"**WHOIS:** {details['whois']}\n**SSL/TLS Config:** {details['ssl_labs']}"
    }

async def check_google_safe_browsing(url: str):
    """
    Checks a URL against the Google Safe Browsing API.
    """
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        print("Warning: GOOGLE_API_KEY not found. Skipping safe browsing check.")
        return {
            "score": 0.5,
            "threat_type": "MISSING_API_KEY",
            "source": "Google Safe Browsing",
            "details": "Google Safe Browsing check could not be performed. API key is missing."
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
                "source": "Google Safe Browsing",
                "details": f"Identified as a potential threat for **{threat_type.replace('_', ' ').title()}**."
            }
        else:
            return {
                "score": 0.1,  # Low score for safe sites
                "threat_type": "SAFE",
                "source": "Google Safe Browsing",
                "details": "Not known to host malicious content."
            }
    except requests.exceptions.RequestException as e:
        print(f"Error calling Google Safe Browsing API: {e}")
        return {
            "score": 0.5,
            "threat_type": "API_ERROR",
            "source": "Google Safe Browsing",
            "details": f"API Error: {e}"
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

    # Perform reputation checks first, then pass the captured page data through
    # the LLM analyzer so the final score uses the extracted forms/text/links too.
    google_result = await check_google_safe_browsing(url_to_check)
    openphish_result = await check_openphish(url_to_check)
    spamhaus_result = await check_spamhaus(url_to_check)
    domain_details_result = await get_domain_details(url_to_check)

    all_results = [google_result, openphish_result, spamhaus_result, domain_details_result]
    llm_scan_report = {
        **url_data,
        "reputation_checks": all_results,
    }
    final_analysis = analyze_scan_report(llm_scan_report, google_result, use_gemini=True)
    final_analysis["reputation_checks"] = all_results
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