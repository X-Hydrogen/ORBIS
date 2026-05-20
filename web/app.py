#!/usr/bin/env python3
"""
Orbis Web Interface — Flask-based web UI for the Quantum Chemistry AI Scientist

Usage:
    python3 web/app.py              # Start on http://localhost:5000
    python3 web/app.py --port 8080  # Custom port
    python3 web/app.py --host 0.0.0.0 --port 8888  # Public access
"""

import json
import os
import queue
import sys
import threading
import time
import uuid
from pathlib import Path

ORBIS_HOME = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ORBIS_HOME))

from flask import (
    Flask, render_template_string, request, jsonify,
    Response, send_file, send_from_directory
)

from agent.orbis_agent import OrbisAgent

app = Flask(__name__)
app.config["SECRET_KEY"] = os.urandom(24).hex()

# ── Job management ────────────────────────────────────────────────

jobs = {}  # job_id -> {status, progress, result, files, ...}
job_queues = {}  # job_id -> queue.Queue for SSE streaming


def _run_agent_job(job_id: str, goal: str, context: str = ""):
    """Background thread: run the Orbis agent and stream progress."""
    job = jobs[job_id]
    q = job_queues[job_id]

    try:
        job["status"] = "running"
        q.put(json.dumps({"type": "status", "status": "running",
                          "message": "Starting Orbis Agent..."}))

        agent = OrbisAgent(verbose=False)

        # Monkey-patch the log method to stream progress
        original_log = agent._log

        def streaming_log(msg: str):
            original_log(msg)
            q.put(json.dumps({"type": "log", "message": msg},
                            ensure_ascii=False))

        agent._log = streaming_log

        # Run the agent
        result = agent.run(goal, extra_context=context)

        job["status"] = "complete"
        job["result"] = result["final_response"]
        job["iterations"] = result["iterations"]

        # Look for generated paper files
        paper_files = _find_paper_files()
        job["files"] = paper_files

        q.put(json.dumps({
            "type": "complete",
            "status": "complete",
            "message": "Agent finished successfully!",
            "iterations": result["iterations"],
            "files": paper_files,
        }, ensure_ascii=False))

    except Exception as e:
        import traceback
        job["status"] = "error"
        job["error"] = str(e)
        q.put(json.dumps({
            "type": "error",
            "status": "error",
            "message": f"Error: {e}",
        }))


def _find_paper_files() -> list:
    """Find generated paper files in the workspace."""
    workspace = Path("/home/quantum/xhy/orbis/workspace")
    files = []

    # Find paper directories
    for paper_dir in sorted(workspace.glob("paper_*"), reverse=True):
        if paper_dir.is_dir():
            # Look for .tex, .pdf, .docx files
            for ext, mime in [(".pdf", "application/pdf"),
                              (".docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
                              (".tex", "text/x-tex")]:
                for f in sorted(paper_dir.rglob(f"*{ext}")):
                    files.append({
                        "name": f.name,
                        "path": str(f),
                        "size": f.stat().st_size,
                        "mime": mime,
                    })
            # Also look in tex/ subdirectory
            tex_dir = paper_dir / "tex"
            if tex_dir.is_dir():
                for ext, mime in [(".pdf", "application/pdf"),
                                  (".tex", "text/x-tex")]:
                    for f in sorted(tex_dir.glob(f"*{ext}")):
                        files.append({
                            "name": f"tex/{f.name}",
                            "path": str(f),
                            "size": f.stat().st_size,
                            "mime": mime,
                        })

    if files:
        return files[:10]  # Limit to most recent 10

    # Fallback: check paper_output in orbis root
    paper_output = Path("/home/quantum/xhy/orbis/paper_output")
    if paper_output.is_dir():
        for ext, mime in [(".pdf", "application/pdf"),
                          (".docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
                          (".tex", "text/x-tex")]:
            for f in sorted(paper_output.rglob(f"*{ext}")):
                files.append({
                    "name": f.name,
                    "path": str(f),
                    "size": f.stat().st_size,
                    "mime": mime,
                })

    return files[:10]


# ── Routes ────────────────────────────────────────────────────────

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>🔬 Orbis — Quantum Chemistry AI Scientist</title>
<style>
  :root {
    --bg: #0a0a1a;
    --card-bg: #111133;
    --text: #e0e0f0;
    --accent: #4472C4;
    --accent-glow: #6688DD;
    --success: #44CC66;
    --error: #CC4444;
    --border: #222244;
    --input-bg: #0d0d28;
    --log-bg: #080820;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 40px 20px;
  }
  .container { max-width: 900px; width: 100%; }

  h1 {
    font-size: 2.5em;
    text-align: center;
    margin-bottom: 8px;
    background: linear-gradient(135deg, #4472C4, #44CCAA);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }
  .subtitle {
    text-align: center;
    color: #8888AA;
    font-size: 1.1em;
    margin-bottom: 40px;
  }

  .card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 30px;
    margin-bottom: 24px;
    box-shadow: 0 4px 24px rgba(0, 0, 0, 0.3);
  }

  textarea {
    width: 100%;
    min-height: 100px;
    background: var(--input-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    color: var(--text);
    padding: 16px;
    font-size: 1.05em;
    font-family: inherit;
    resize: vertical;
    transition: border-color 0.2s;
  }
  textarea:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 0 3px rgba(68, 114, 196, 0.15);
  }

  .btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 14px 32px;
    border: none;
    border-radius: 10px;
    font-size: 1.05em;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
    font-family: inherit;
  }
  .btn-primary {
    background: var(--accent);
    color: white;
    width: 100%;
    justify-content: center;
    margin-top: 16px;
  }
  .btn-primary:hover:not(:disabled) {
    background: var(--accent-glow);
    box-shadow: 0 4px 20px rgba(68, 114, 196, 0.4);
    transform: translateY(-1px);
  }
  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .examples {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 12px;
  }
  .example-tag {
    background: rgba(68, 114, 196, 0.15);
    border: 1px solid rgba(68, 114, 196, 0.3);
    border-radius: 20px;
    padding: 6px 14px;
    font-size: 0.85em;
    cursor: pointer;
    transition: all 0.2s;
    color: #88AADD;
  }
  .example-tag:hover {
    background: rgba(68, 114, 196, 0.3);
    border-color: var(--accent);
    color: white;
  }

  #progress {
    display: none;
    margin-top: 16px;
  }
  #progress.active { display: block; }

  .status-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 14px;
    border-radius: 20px;
    font-size: 0.9em;
    font-weight: 600;
    margin-bottom: 12px;
  }
  .status-running {
    background: rgba(68, 114, 196, 0.2);
    border: 1px solid var(--accent);
    color: #88AAFF;
  }
  .status-complete {
    background: rgba(68, 204, 102, 0.2);
    border: 1px solid var(--success);
    color: #66EE88;
  }
  .status-error {
    background: rgba(204, 68, 68, 0.2);
    border: 1px solid var(--error);
    color: #EE6666;
  }

  .spinner {
    display: inline-block;
    width: 14px; height: 14px;
    border: 2px solid transparent;
    border-top-color: currentColor;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }

  .log-console {
    background: var(--log-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 16px;
    max-height: 400px;
    overflow-y: auto;
    font-family: 'JetBrains Mono', 'Cascadia Code', 'Fira Code', monospace;
    font-size: 0.85em;
    line-height: 1.5;
    white-space: pre-wrap;
    word-break: break-all;
    color: #8888AA;
  }

  .files-list { margin-top: 16px; }
  .file-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    background: rgba(68, 204, 102, 0.08);
    border: 1px solid rgba(68, 204, 102, 0.2);
    border-radius: 10px;
    margin-bottom: 8px;
    transition: all 0.2s;
    text-decoration: none;
    color: var(--text);
  }
  .file-item:hover {
    background: rgba(68, 204, 102, 0.15);
    border-color: var(--success);
  }
  .file-icon { font-size: 1.5em; }
  .file-name { font-weight: 600; flex: 1; }
  .file-size { color: #8888AA; font-size: 0.85em; }

  .download-all {
    display: inline-block;
    margin-top: 12px;
    padding: 10px 24px;
    background: var(--success);
    color: white;
    border-radius: 8px;
    text-decoration: none;
    font-weight: 600;
    font-size: 0.95em;
    transition: all 0.2s;
  }
  .download-all:hover {
    box-shadow: 0 4px 16px rgba(68, 204, 102, 0.4);
    transform: translateY(-1px);
  }
</style>
</head>
<body>
<div class="container">

  <h1>🔬 Orbis</h1>
  <p class="subtitle">Quantum Chemistry AI Scientist — Input your goal, get a complete research paper</p>

  <div class="card">
    <textarea id="goalInput"
              placeholder="Describe your research goal here...
Examples:
  • I want to study the detailed quantum chemical properties of the H2O dimer
  • Optimize benzene at B3LYP-D3(BJ)/def2-TZVP and analyze its electronic structure
  • Find the transition state for the Diels-Alder reaction between butadiene and ethylene

The agent will run ORCA calculations and generate a complete LaTeX + Word paper."></textarea>

    <div class="examples">
      <span class="example-tag" onclick="setGoal('I want to study the detailed quantum chemical properties of the H2O dimer, including geometry optimization, frequency analysis, binding energy, HOMO-LUMO gap, and generate a complete research paper in LaTeX and Word format.')">💧 H₂O Dimer</span>
      <span class="example-tag" onclick="setGoal('Optimize benzene molecule at B3LYP-D3(BJ)/def2-TZVP level, compute its vibrational frequencies and IR spectrum, analyze its HOMO-LUMO gap, and generate a full research paper.')">⬡ Benzene</span>
      <span class="example-tag" onclick="setGoal('Study the formaldehyde molecule (CH2O): optimize geometry, compute frequencies, analyze electronic structure with HOMO/LUMO, and generate a complete paper.')">⚛ CH₂O</span>
    </div>

    <button class="btn btn-primary" id="submitBtn" onclick="startJob()">
      🚀 Launch Research
    </button>
  </div>

  <div id="progress">
    <div class="card">
      <div id="statusBadge"></div>
      <div class="log-console" id="logConsole"></div>
      <div class="files-list" id="filesList"></div>
    </div>
  </div>

</div>

<script>
let eventSource = null;
let jobId = null;

function setGoal(text) {
  document.getElementById('goalInput').value = text;
}

async function startJob() {
  const goal = document.getElementById('goalInput').value.trim();
  if (!goal) return;

  const submitBtn = document.getElementById('submitBtn');
  submitBtn.disabled = true;
  submitBtn.innerHTML = '<span class="spinner"></span> Launching...';

  // Start job
  const resp = await fetch('/api/start', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({goal: goal})
  });
  const data = await resp.json();
  jobId = data.job_id;

  // Show progress
  document.getElementById('progress').classList.add('active');
  document.getElementById('statusBadge').innerHTML =
    '<span class="status-badge status-running"><span class="spinner"></span> Running...</span>';
  document.getElementById('logConsole').textContent = '';
  document.getElementById('filesList').innerHTML = '';

  submitBtn.innerHTML = '⏳ Agent Running...';

  // Connect SSE
  eventSource = new EventSource('/api/stream/' + jobId);

  eventSource.onmessage = function(event) {
    const msg = JSON.parse(event.data);

    if (msg.type === 'log') {
      const log = document.getElementById('logConsole');
      log.textContent += msg.message + '\\n';
      log.scrollTop = log.scrollHeight;
    } else if (msg.type === 'complete') {
      document.getElementById('statusBadge').innerHTML =
        '<span class="status-badge status-complete">✅ Complete — ' +
        msg.iterations + ' iterations</span>';
      submitBtn.innerHTML = '🚀 Launch Research';
      submitBtn.disabled = false;

      // Show files
      if (msg.files && msg.files.length > 0) {
        let html = '<h3 style="margin-top:16px;color:#66EE88;">📄 Generated Files</h3>';
        for (const f of msg.files) {
          html += '<a class="file-item" href="/api/download?path=' +
            encodeURIComponent(f.path) + '" download>' +
            '<span class="file-icon">' + fileIcon(f.name) + '</span>' +
            '<span class="file-name">' + f.name + '</span>' +
            '<span class="file-size">' + formatSize(f.size) + '</span>' +
            '</a>';
        }
        document.getElementById('filesList').innerHTML = html;
      }

      eventSource.close();
    } else if (msg.type === 'error') {
      document.getElementById('statusBadge').innerHTML =
        '<span class="status-badge status-error">❌ ' + msg.message + '</span>';
      submitBtn.innerHTML = '🚀 Launch Research';
      submitBtn.disabled = false;
      eventSource.close();
    }
  };

  eventSource.onerror = function() {
    console.log('SSE connection closed');
    submitBtn.innerHTML = '🚀 Launch Research';
    submitBtn.disabled = false;
  };
}

function fileIcon(name) {
  if (name.endsWith('.pdf')) return '📕';
  if (name.endsWith('.docx')) return '📘';
  if (name.endsWith('.tex')) return '📝';
  if (name.endsWith('.png')) return '🖼️';
  return '📄';
}

function formatSize(bytes) {
  if (!bytes) return '';
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024*1024) return (bytes/1024).toFixed(1) + ' KB';
  return (bytes/(1024*1024)).toFixed(1) + ' MB';
}
</script>
</body>
</html>"""


@app.route("/")
def index():
    return render_template_string(HTML_TEMPLATE)


@app.route("/api/start", methods=["POST"])
def api_start():
    """Start a new Orbis agent job."""
    data = request.get_json()
    goal = data.get("goal", "").strip()
    if not goal:
        return jsonify({"error": "No goal provided"}), 400

    job_id = uuid.uuid4().hex[:12]
    jobs[job_id] = {
        "id": job_id,
        "goal": goal,
        "status": "starting",
        "created_at": time.time(),
        "result": None,
        "files": [],
    }
    job_queues[job_id] = queue.Queue()

    # Start background thread
    thread = threading.Thread(
        target=_run_agent_job,
        args=(job_id, goal),
        daemon=True,
    )
    thread.start()

    return jsonify({"job_id": job_id, "status": "starting"})


@app.route("/api/stream/<job_id>")
def api_stream(job_id):
    """SSE endpoint for job progress."""
    if job_id not in job_queues:
        return jsonify({"error": "Job not found"}), 404

    q = job_queues[job_id]

    def generate():
        while True:
            try:
                msg = q.get(timeout=30)
                yield f"data: {msg}\n\n"
                if '"type": "complete"' in msg or '"type": "error"' in msg:
                    break
            except queue.Empty:
                yield f"data: {json.dumps({'type': 'ping'})}\n\n"

    return Response(
        generate(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@app.route("/api/download")
def api_download():
    """Download a generated file."""
    filepath = request.args.get("path", "")
    if not filepath or not Path(filepath).exists():
        return jsonify({"error": "File not found"}), 404

    path = Path(filepath)
    return send_file(
        path,
        as_attachment=True,
        download_name=path.name,
    )


@app.route("/api/status/<job_id>")
def api_status(job_id):
    """Get job status."""
    if job_id not in jobs:
        return jsonify({"error": "Job not found"}), 404
    job = jobs[job_id]
    return jsonify({
        "id": job["id"],
        "status": job["status"],
        "iterations": job.get("iterations"),
        "files": job.get("files", []),
    })


# ── Main ──────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Orbis Web Interface")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address")
    parser.add_argument("--port", type=int, default=5000, help="Port")
    parser.add_argument("--debug", action="store_true", help="Debug mode")
    args = parser.parse_args()

    print("🔬 Orbis Web Interface")
    print(f"   Address: http://{args.host}:{args.port}")
    print(f"   ORCA Bin: {os.environ.get('ORCA_BIN', '/home/quantum/tools/orca_6_1_0_avx2/orca')}")
    print()

    app.run(host=args.host, port=args.port, debug=args.debug, threaded=True)
