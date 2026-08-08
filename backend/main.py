from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from typing import List
import uvicorn

# Initialize the FastAPI app
app = FastAPI(
    title="Theft Alert API",
    description="Backend server for Team Paradox Phishing and Fraud Detection",
    version="1.0.0"
)

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
    # Example endpoint to handle traditional HTTP POST requests
    return {"message": "URL received for scanning", "data": url_data}

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