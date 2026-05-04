#!/usr/bin/env python3
"""
OTA Server for IPA signing and installation
Supports signing with Apple ID and serving signed IPAs
"""

from flask import Flask, request, jsonify, send_file, render_template_string
import os
import subprocess
import tempfile
import shutil
from pathlib import Path
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Configuration
UPLOAD_FOLDER = '/tmp/ota-uploads'
SIGNED_FOLDER = '/tmp/ota-signed'
IPA_URL = 'https://github.com/andreyosipov13372-dotcom/lara/releases/latest/download/lara.ipa'

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(SIGNED_FOLDER, exist_ok=True)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LARA OTA Installer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            max-width: 500px;
            width: 100%;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        .status {
            background: #f0f0f0;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
            font-size: 14px;
        }
        .status.success { background: #d4edda; color: #155724; }
        .status.error { background: #f8d7da; color: #721c24; }
        .status.info { background: #d1ecf1; color: #0c5460; }
        button {
            width: 100%;
            padding: 15px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            margin-bottom: 10px;
            transition: all 0.3s;
        }
        button:hover { background: #5568d3; transform: translateY(-2px); }
        button:disabled { background: #ccc; cursor: not-allowed; transform: none; }
        .progress {
            width: 100%;
            height: 4px;
            background: #f0f0f0;
            border-radius: 2px;
            overflow: hidden;
            margin-bottom: 20px;
            display: none;
        }
        .progress-bar {
            height: 100%;
            background: #667eea;
            width: 0%;
            transition: width 0.3s;
        }
        .info-box {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 10px;
            margin-top: 20px;
            font-size: 13px;
            color: #666;
        }
        .info-box strong { color: #333; display: block; margin-bottom: 5px; }
        .log {
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 15px;
            border-radius: 10px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 200px;
            overflow-y: auto;
            margin-top: 20px;
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 LARA OTA Installer</h1>
        <p class="subtitle">TrollStore установщик с автоподписью</p>

        <div id="status" class="status info">
            Готов к установке
        </div>

        <div class="progress" id="progress">
            <div class="progress-bar" id="progressBar"></div>
        </div>

        <button id="installBtn" onclick="startInstall()">
            📥 Скачать и подписать LARA
        </button>

        <button id="installSignedBtn" onclick="installSigned()" style="display:none;">
            ✅ Установить подписанную версию
        </button>

        <div class="info-box">
            <strong>ℹ️ Информация:</strong>
            • Автоматическая подпись с Apple ID<br>
            • Поддержка iOS 17.0 - 17.6.1<br>
            • TrollStore установка через LARA<br>
            • Работает 7 дней до переподписи
        </div>

        <div id="log" class="log"></div>
    </div>

    <script>
        function addLog(msg) {
            const log = document.getElementById('log');
            log.style.display = 'block';
            log.innerHTML += msg + '<br>';
            log.scrollTop = log.scrollHeight;
        }

        function setStatus(msg, type) {
            const status = document.getElementById('status');
            status.textContent = msg;
            status.className = 'status ' + type;
        }

        function setProgress(percent) {
            const progress = document.getElementById('progress');
            const bar = document.getElementById('progressBar');
            progress.style.display = 'block';
            bar.style.width = percent + '%';
        }

        async function startInstall() {
            const btn = document.getElementById('installBtn');
            btn.disabled = true;
            btn.textContent = '⏳ Подписываю...';

            setStatus('Скачиваю IPA...', 'info');
            setProgress(10);
            addLog('[1/4] Скачивание LARA IPA...');

            try {
                const response = await fetch('/api/sign', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                });

                const data = await response.json();

                if (data.success) {
                    setProgress(100);
                    setStatus('✅ Подпись завершена!', 'success');
                    addLog('[4/4] Готово! IPA подписана и готова к установке');

                    document.getElementById('installSignedBtn').style.display = 'block';
                    btn.style.display = 'none';
                } else {
                    throw new Error(data.error || 'Ошибка подписи');
                }
            } catch (error) {
                setStatus('❌ Ошибка: ' + error.message, 'error');
                addLog('ERROR: ' + error.message);
                btn.disabled = false;
                btn.textContent = '🔄 Попробовать снова';
            }
        }

        async function installSigned() {
            setStatus('Открываю установщик...', 'info');
            addLog('Перенаправление на itms-services...');

            // iOS OTA installation
            window.location.href = 'itms-services://?action=download-manifest&url=' +
                encodeURIComponent(window.location.origin + '/manifest.plist');
        }

        // Update progress during signing
        setInterval(async () => {
            if (document.getElementById('installBtn').disabled) {
                try {
                    const response = await fetch('/api/status');
                    const data = await response.json();
                    if (data.progress) {
                        setProgress(data.progress);
                        if (data.message) {
                            addLog(data.message);
                        }
                    }
                } catch (e) {}
            }
        }, 1000);
    </script>
</body>
</html>
"""

MANIFEST_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>items</key>
    <array>
        <dict>
            <key>assets</key>
            <array>
                <dict>
                    <key>kind</key>
                    <string>software-package</string>
                    <key>url</key>
                    <string>{IPA_URL}</string>
                </dict>
            </array>
            <key>metadata</key>
            <dict>
                <key>bundle-identifier</key>
                <string>com.lara.app</string>
                <key>bundle-version</key>
                <string>1.0</string>
                <key>kind</key>
                <string>software</string>
                <key>title</key>
                <string>LARA TrollStore</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
"""

signing_status = {'progress': 0, 'message': ''}

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/manifest.plist')
def manifest():
    signed_ipa_url = request.host_url + 'download/signed.ipa'
    manifest_content = MANIFEST_TEMPLATE.format(IPA_URL=signed_ipa_url)
    return manifest_content, 200, {'Content-Type': 'application/xml'}

@app.route('/api/status')
def status():
    return jsonify(signing_status)

@app.route('/api/sign', methods=['POST'])
def sign_ipa():
    global signing_status

    try:
        signing_status = {'progress': 10, 'message': '[1/4] Скачивание IPA...'}

        # Download IPA
        ipa_path = os.path.join(UPLOAD_FOLDER, 'lara.ipa')
        subprocess.run(['wget', '-O', ipa_path, IPA_URL], check=True)

        signing_status = {'progress': 30, 'message': '[2/4] Подготовка к подписи...'}

        # Sign with zsign (will be installed on server)
        signed_path = os.path.join(SIGNED_FOLDER, 'signed.ipa')

        signing_status = {'progress': 60, 'message': '[3/4] Подпись IPA...'}

        # Use zsign for signing
        # Note: Apple ID credentials should be configured on server
        subprocess.run([
            'zsign',
            '-k', '/root/.zsign/cert.p12',
            '-m', '/root/.zsign/profile.mobileprovision',
            '-o', signed_path,
            ipa_path
        ], check=True)

        signing_status = {'progress': 100, 'message': '[4/4] Готово!'}

        return jsonify({'success': True, 'url': '/download/signed.ipa'})

    except Exception as e:
        logging.error(f"Signing error: {e}")
        signing_status = {'progress': 0, 'message': f'Ошибка: {str(e)}'}
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/download/signed.ipa')
def download_signed():
    signed_path = os.path.join(SIGNED_FOLDER, 'signed.ipa')
    if os.path.exists(signed_path):
        return send_file(signed_path, mimetype='application/octet-stream', as_attachment=True)
    return jsonify({'error': 'Signed IPA not found'}), 404

@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'service': 'lara-ota-server'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
