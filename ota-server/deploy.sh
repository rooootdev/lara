#!/bin/bash
# Deploy OTA Server to Oracle Cloud

set -e

echo "🚀 Deploying LARA OTA Server..."

# Update system
echo "📦 Updating system packages..."
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv wget unzip git

# Install zsign for IPA signing
echo "🔐 Installing zsign..."
cd /tmp
wget https://github.com/zhlynn/zsign/releases/download/1.1.2/zsign-linux-x86_64.zip
unzip zsign-linux-x86_64.zip
sudo mv zsign /usr/local/bin/
sudo chmod +x /usr/local/bin/zsign
rm zsign-linux-x86_64.zip

# Create directories
echo "📁 Creating directories..."
sudo mkdir -p /opt/lara-ota
sudo mkdir -p /root/.zsign
sudo chown -R $USER:$USER /opt/lara-ota

# Copy server files
echo "📋 Copying server files..."
cd /opt/lara-ota
cat > server.py << 'SERVEREOF'
SERVEREOF

# Install Python dependencies
echo "🐍 Installing Python dependencies..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install Flask==3.0.0 Werkzeug==3.0.1 gunicorn==21.2.0 requests==2.31.0

# Create systemd service
echo "⚙️ Creating systemd service..."
sudo tee /etc/systemd/system/lara-ota.service > /dev/null << 'EOF'
[Unit]
Description=LARA OTA Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/lara-ota
Environment="PATH=/opt/lara-ota/venv/bin"
ExecStart=/opt/lara-ota/venv/bin/gunicorn --bind 0.0.0.0:8080 --workers 4 server:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo "🔄 Starting service..."
sudo systemctl daemon-reload
sudo systemctl enable lara-ota
sudo systemctl start lara-ota

# Install Cloudflare Tunnel
echo "☁️ Installing Cloudflare Tunnel..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
rm cloudflared-linux-amd64.deb

echo ""
echo "✅ OTA Server deployed successfully!"
echo ""
echo "📝 Next steps:"
echo "1. Configure Apple ID signing:"
echo "   - Export your certificate as .p12 file"
echo "   - Download provisioning profile"
echo "   - Copy to /root/.zsign/"
echo ""
echo "2. Setup Cloudflare Tunnel:"
echo "   cloudflared tunnel login"
echo "   cloudflared tunnel create lara-ota"
echo "   cloudflared tunnel route dns lara-ota lara.yourdomain.com"
echo ""
echo "3. Create tunnel config:"
echo "   sudo mkdir -p /etc/cloudflared"
echo "   sudo nano /etc/cloudflared/config.yml"
echo ""
echo "   Add:"
echo "   tunnel: <TUNNEL-ID>"
echo "   credentials-file: /root/.cloudflared/<TUNNEL-ID>.json"
echo "   ingress:"
echo "     - hostname: lara.yourdomain.com"
echo "       service: http://localhost:8080"
echo "     - service: http_status:404"
echo ""
echo "4. Start tunnel:"
echo "   sudo cloudflared service install"
echo "   sudo systemctl start cloudflared"
echo ""
echo "🌐 Server status: sudo systemctl status lara-ota"
echo "📊 Server logs: sudo journalctl -u lara-ota -f"
