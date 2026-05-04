#!/bin/bash
# Quick deploy script - uploads and runs deployment on Oracle server

SERVER="ubuntu@79.72.18.198"
SSH_KEY="/home/orkenlk/Загрузки/ssh-key-2026-04-29 (1).key"

echo "📤 Uploading OTA server files to Oracle Cloud..."

# Create remote directory
ssh -i "$SSH_KEY" $SERVER "mkdir -p ~/lara-ota-deploy"

# Upload files
scp -i "$SSH_KEY" server.py $SERVER:~/lara-ota-deploy/
scp -i "$SSH_KEY" requirements.txt $SERVER:~/lara-ota-deploy/
scp -i "$SSH_KEY" deploy.sh $SERVER:~/lara-ota-deploy/

echo "🚀 Running deployment on server..."

# Run deployment
ssh -i "$SSH_KEY" $SERVER "cd ~/lara-ota-deploy && chmod +x deploy.sh && sudo ./deploy.sh"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "🔗 Connect to server:"
echo "   ssh -i '$SSH_KEY' $SERVER"
echo ""
echo "📊 Check status:"
echo "   ssh -i '$SSH_KEY' $SERVER 'sudo systemctl status lara-ota'"
