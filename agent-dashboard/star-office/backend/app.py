#!/usr/bin/env python3
"""Star Office UI - Backend State Service"""

from flask import Flask, jsonify, send_from_directory, make_response, request, session
from datetime import datetime, timedelta
import json
import hashlib
import base64
import os
import random
import math
import re
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path
from security_utils import is_production_mode, is_strong_secret, is_strong_drawer_pass
from memo_utils import get_yesterday_date_str, sanitize_content, extract_memo_from_file
from store_utils import (
    load_agents_state as _store_load_agents_state,
    save_agents_state as _store_save_agents_state,
    load_asset_positions as _store_load_asset_positions,
    save_asset_positions as _store_save_asset_positions,
    load_asset_defaults as _store_load_asset_defaults,
    save_asset_defaults as _store_save_asset_defaults,
    load_runtime_config as _store_load_runtime_config,
    save_runtime_config as _store_save_runtime_config,
    load_join_keys as _store_load_join_keys,
    save_join_keys as _store_save_join_keys,
)
from room_gen import build_room_gen_prompt

try:
    from PIL import Image
except Exception:
    Image = None

# Paths (project-relative, no hardcoded absolute paths)
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DASH_DIR = os.path.dirname(ROOT_DIR)
AGENT_STATUS_JS = os.path.join(DASH_DIR, "agent-status.js")
ARCHIVE_DIR = os.path.join(DASH_DIR, "log-archive")
ARCHIVE_NAME_RE = re.compile(r"^status-\d{4}-\d{2}-\d{2}\.json$")
MEMORY_DIR = os.path.join(os.path.dirname(ROOT_DIR), "memory")
FRONTEND_DIR = os.path.join(ROOT_DIR, "frontend")
FRONTEND_INDEX_FILE = os.path.join(FRONTEND_DIR, "index.html")
FRONTEND_ELECTRON_STANDALONE_FILE = os.path.join(FRONTEND_DIR, "electron-standalone.html")
STATE_FILE = os.path.join(ROOT_DIR, "state.json")
AGENTS_STATE_FILE = os.path.join(ROOT_DIR, "agents-state.json")
JOIN_KEYS_FILE = os.path.join(ROOT_DIR, "join-keys.json")
FRONTEND_PATH = Path(FRONTEND_DIR)
ASSET_ALLOWED_EXTS = {".png", ".webp", ".jpg", ".jpeg", ".gif", ".svg", ".avif"}
GUEST_AVATARS = [f"guest_role_{i}" for i in range(1, 8)]
ASSET_TEMPLATE_ZIP = os.path.join(ROOT_DIR, "assets-replace-template.zip")
WORKSPACE_DIR = os.path.dirname(ROOT_DIR)
OPENCLAW_WORKSPACE = os.environ.get("OPENCLAW_WORKSPACE") or os.path.join(os.path.expanduser("~"), ".openclaw", "workspace")
IDENTITY_FILE = os.path.join(OPENCLAW_WORKSPACE, "IDENTITY.md")
GEMINI_SCRIPT = os.path.join(WORKSPACE_DIR, "skills", "gemini-image-generate", "scripts", "gemini_image_generate.py")
GEMINI_PYTHON = os.path.join(WORKSPACE_DIR, "skills", "gemini-image-generate", ".venv", "bin", "python")
ROOM_REFERENCE_IMAGE = (
    os.path.join(ROOT_DIR, "assets", "room-reference.webp")
    if os.path.exists(os.path.join(ROOT_DIR, "assets", "room-reference.webp"))
    else os.path.join(ROOT_DIR, "assets", "room-reference.png")
)
BG_HISTORY_DIR = os.path.join(ROOT_DIR, "assets", "bg-history")
ROOM_GALLERY_PUBLIC_DIR = os.path.join(ROOT_DIR, "assets", "room-gallery")
ROOM_GALLERY_MANIFEST_FILE = os.path.join(ROOM_GALLERY_PUBLIC_DIR, "manifest.json")
ROOM_GALLERY_PUBLIC_EXTS = {".webp", ".png", ".jpg", ".jpeg"}
BG_HISTORY_PREFIX = "office_"
LEGACY_HOME_FAVORITES_INDEX_FILE = os.path.join(ROOT_DIR, "assets", "home-favorites", "index.json")
HOME_FAVORITES_INDEX_FILE = os.path.join(BG_HISTORY_DIR, "index.json")
HOME_FAVORITES_MAX = 30
ASSET_POSITIONS_FILE = os.path.join(ROOT_DIR, "asset-positions.json")

# 性能保护：默认关闭“每次打开页面随机换背景”，避免首页首屏被磁盘复制拖慢
AUTO_ROTATE_HOME_ON_PAGE_OPEN = (os.getenv("AUTO_ROTATE_HOME_ON_PAGE_OPEN", "0").strip().lower() in {"1", "true", "yes", "on"})
AUTO_ROTATE_MIN_INTERVAL_SECONDS = int(os.getenv("AUTO_ROTATE_MIN_INTERVAL_SECONDS", "60"))
_last_home_rotate_at = 0
ASSET_DEFAULTS_FILE = os.path.join(ROOT_DIR, "asset-defaults.json")
RUNTIME_CONFIG_FILE = os.path.join(ROOT_DIR, "runtime-config.json")

GEMINI_SKILL_MISSING_MSG = (
    "Image generation skill not installed (agent-dashboard/skills/gemini-image-generate). "
    "See star-office/SKILL.md section 4.1."
)

# Canonical agent states: single source of truth for validation and mapping
VALID_AGENT_STATES = frozenset({"idle", "writing", "researching", "executing", "syncing", "error"})
WORKING_STATES = frozenset({"writing", "researching", "executing"})  # subset used for auto-idle TTL
STATE_TO_AREA_MAP = {
    "idle": "center_room",
    "writing": "cat_room",
    "researching": "cat_room",
    "executing": "cat_room",
    "syncing": "cat_room",
    "error": "error",
}


app = Flask(__name__, static_folder=FRONTEND_DIR, static_url_path="/static")
app.secret_key = os.getenv("FLASK_SECRET_KEY") or os.getenv("STAR_OFFICE_SECRET") or "star-office-dev-secret-change-me"

# Session hardening
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=is_production_mode(),
    PERMANENT_SESSION_LIFETIME=timedelta(hours=12),
)

# Guard join-agent critical section to enforce per-key concurrency under parallel requests
join_lock = threading.Lock()

# Async background task registry for long-running operations (e.g. image generation)
# Avoids Cloudflare 524 timeout (100s limit) by letting frontend poll for completion.
_bg_tasks = {}  # task_id -> {"status": "pending"|"done"|"error", "result": ..., "error": ..., "created_at": ...}
_bg_tasks_lock = threading.Lock()

# Generate a version timestamp once at server startup for cache busting
VERSION_TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
ASSET_DRAWER_PASS_DEFAULT = os.getenv("ASSET_DRAWER_PASS", "1234")

if is_production_mode():
    hardening_errors = []
    if not is_strong_secret(str(app.secret_key)):
        hardening_errors.append("FLASK_SECRET_KEY / STAR_OFFICE_SECRET is weak (need >=24 chars, non-default)")
    if not is_strong_drawer_pass(ASSET_DRAWER_PASS_DEFAULT):
        hardening_errors.append("ASSET_DRAWER_PASS is weak (do not use default 1234; recommend >=8 chars)")
    if hardening_errors:
        raise RuntimeError("Security hardening check failed in production mode: " + "; ".join(hardening_errors))


def _is_asset_editor_authed() -> bool:
    return bool(session.get("asset_editor_authed"))


def _require_asset_editor_auth():
    if _is_asset_editor_authed():
        return None
    return jsonify({"ok": False, "code": "UNAUTHORIZED", "msg": "Asset editor auth required"}), 401


@app.after_request
def add_no_cache_headers(response):
    """Apply cache policy by path:
    - HTML/API/state: no-cache (always fresh)
    - /static assets (2xx only): long cache (filenames are versioned with ?v=VERSION_TIMESTAMP)
    - /static assets (non-2xx, e.g. 404): no-cache to prevent CDN from caching errors
    """
    path = (request.path or "")
    if path.startswith('/static/') and 200 <= response.status_code < 300:
        response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        response.headers.pop("Pragma", None)
        response.headers.pop("Expires", None)
    else:
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate, max-age=0"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    return response

# Default state
DEFAULT_STATE = {
    "state": "idle",
    "detail": "等待任务中...",
    "progress": 0,
    "updated_at": datetime.now().isoformat()
}


def load_state():
    """Load state from file.

    Includes a simple auto-idle mechanism:
    - If the last update is older than ttl_seconds (default 25s)
      and the state is a "working" state, we fall back to idle.

    This avoids the UI getting stuck at the desk when no new updates arrive.
    """
    state = None
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                state = json.load(f)
        except Exception:
            state = None

    if not isinstance(state, dict):
        state = dict(DEFAULT_STATE)

    # Auto-idle
    try:
        ttl = int(state.get("ttl_seconds", 300))
        updated_at = state.get("updated_at")
        s = state.get("state", "idle")
        if updated_at and s in WORKING_STATES:
            # tolerate both with/without timezone
            dt = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
            # Use UTC for aware datetimes; local time for naive.
            if dt.tzinfo:
                from datetime import timezone
                age = (datetime.now(timezone.utc) - dt.astimezone(timezone.utc)).total_seconds()
            else:
                age = (datetime.now() - dt).total_seconds()
            if age > ttl:
                state["state"] = "idle"
                state["detail"] = "待命中（自动回到休息区）"
                state["progress"] = 0
                state["updated_at"] = datetime.now().isoformat()
                # persist the auto-idle so every client sees it consistently
                try:
                    save_state(state)
                except Exception:
                    pass
    except Exception:
        pass

    return state


def get_office_name_from_identity():
    """Read office display name from OpenClaw workspace IDENTITY.md (Name field) -> 'XXX的办公室'."""
    if not os.path.isfile(IDENTITY_FILE):
        return None
    try:
        with open(IDENTITY_FILE, "r", encoding="utf-8") as f:
            content = f.read()
        m = re.search(r"-\s*\*\*Name:\*\*\s*(.+)", content)
        if m:
            name = m.group(1).strip().replace("\r", "").split("\n")[0].strip()
            return f"{name}的办公室" if name else None
    except Exception:
        pass
    return None


def save_state(state: dict):
    """Save state to file"""
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def ensure_electron_standalone_snapshot():
    """Create Electron standalone frontend snapshot once if missing.

    The snapshot is intentionally decoupled from the browser page:
    - browser uses frontend/index.html
    - Electron uses frontend/electron-standalone.html
    """
    if os.path.exists(FRONTEND_ELECTRON_STANDALONE_FILE):
        return
    try:
        shutil.copy2(FRONTEND_INDEX_FILE, FRONTEND_ELECTRON_STANDALONE_FILE)
        print(f"[standalone] created: {FRONTEND_ELECTRON_STANDALONE_FILE}")
    except Exception as e:
        print(f"[standalone] create failed: {e}")


# Initialize state
if not os.path.exists(STATE_FILE):
    save_state(DEFAULT_STATE)
ensure_electron_standalone_snapshot()


_INDEX_HTML_CACHE = None
_INDEX_HTML_MTIME = None


def _frontend_assets_mtime() -> float:
    """Highest mtime across frontend static assets — used as a cache-bust version
    so editing any asset invalidates the browser cache without a server restart."""
    latest = 0.0
    for entry in os.scandir(FRONTEND_DIR):
        if entry.is_file() and entry.name.rsplit(".", 1)[-1].lower() in {
            "webp", "png", "jpg", "jpeg", "gif", "svg", "js", "css", "html"
        }:
            m = entry.stat().st_mtime
            if m > latest:
                latest = m
    return latest


def _index_html_response():
    """Serve index.html; reload from disk when the file or any asset changes."""
    global _INDEX_HTML_CACHE, _INDEX_HTML_MTIME
    html_mtime = os.path.getmtime(FRONTEND_INDEX_FILE)
    assets_mtime = _frontend_assets_mtime()
    sig = (html_mtime, assets_mtime)
    if _INDEX_HTML_CACHE is None or _INDEX_HTML_MTIME != sig:
        version = datetime.fromtimestamp(max(html_mtime, assets_mtime)).strftime("%Y%m%d_%H%M%S")
        with open(FRONTEND_INDEX_FILE, "r", encoding="utf-8") as f:
            _INDEX_HTML_CACHE = f.read().replace("{{VERSION_TIMESTAMP}}", version)
        _INDEX_HTML_MTIME = sig
    resp = make_response(_INDEX_HTML_CACHE)
    resp.headers["Content-Type"] = "text/html; charset=utf-8"
    return resp


@app.route("/favicon.ico", methods=["GET"])
def favicon():
    return send_from_directory(FRONTEND_DIR, "favicon.ico", mimetype="image/vnd.microsoft.icon")


@app.route("/", methods=["GET"])
def index():
    """Serve the pixel office UI with built-in version cache busting"""
    # 默认禁用页面打开即换背景，避免首屏慢
    # 如需启用，可配置 AUTO_ROTATE_HOME_ON_PAGE_OPEN=1
    _maybe_apply_random_home_favorite()
    return _index_html_response()


@app.route("/electron-standalone", methods=["GET"])
def electron_standalone_page():
    """Serve Electron-only standalone frontend page."""
    ensure_electron_standalone_snapshot()
    target = FRONTEND_ELECTRON_STANDALONE_FILE
    if not os.path.exists(target):
        target = FRONTEND_INDEX_FILE
    with open(target, "r", encoding="utf-8") as f:
        html = f.read()
    html = html.replace("{{VERSION_TIMESTAMP}}", VERSION_TIMESTAMP)
    resp = make_response(html)
    resp.headers["Content-Type"] = "text/html; charset=utf-8"
    return resp

    resp.headers["Content-Type"] = "text/html; charset=utf-8"
    return resp


@app.route("/join", methods=["GET"])
def join_page():
    """Serve the agent join page"""
    with open(os.path.join(FRONTEND_DIR, "join.html"), "r", encoding="utf-8") as f:
        html = f.read()
    resp = make_response(html)
    resp.headers["Content-Type"] = "text/html; charset=utf-8"
    return resp


@app.route("/invite", methods=["GET"])
def invite_page():
    """Serve human-facing invite instruction page"""
    with open(os.path.join(FRONTEND_DIR, "invite.html"), "r", encoding="utf-8") as f:
        html = f.read()
    resp = make_response(html)
    resp.headers["Content-Type"] = "text/html; charset=utf-8"
    return resp


DEFAULT_AGENTS = [
    {
        "agentId": "star",
        "name": "Star",
        "isMain": True,
        "state": "idle",
        "detail": "待命中，随时准备为你服务",
        "updated_at": datetime.now().isoformat(),
        "area": "center_room",
        "source": "local",
        "joinKey": None,
        "authStatus": "approved",
        "authExpiresAt": None,
        "lastPushAt": None
    }
]


def load_agents_state():
    return _store_load_agents_state(AGENTS_STATE_FILE, DEFAULT_AGENTS)


def save_agents_state(agents):
    _store_save_agents_state(AGENTS_STATE_FILE, agents)


def load_asset_positions():
    return _store_load_asset_positions(ASSET_POSITIONS_FILE)


def save_asset_positions(data):
    _store_save_asset_positions(ASSET_POSITIONS_FILE, data)


def load_asset_defaults():
    return _store_load_asset_defaults(ASSET_DEFAULTS_FILE)


def save_asset_defaults(data):
    _store_save_asset_defaults(ASSET_DEFAULTS_FILE, data)


def load_runtime_config():
    return _store_load_runtime_config(RUNTIME_CONFIG_FILE)


def save_runtime_config(data):
    _store_save_runtime_config(RUNTIME_CONFIG_FILE, data)


def _home_fav_thumb_url(rel_path: str) -> str:
    fn = _safe_history_filename(os.path.basename((rel_path or "").strip()))
    return f"/assets/bg-history/file/{fn}" if fn else ""


def _migrate_legacy_home_favorites_index():
    """One-time: move index from assets/home-favorites/ → assets/bg-history/, fix paths."""
    if os.path.exists(HOME_FAVORITES_INDEX_FILE) or not os.path.exists(LEGACY_HOME_FAVORITES_INDEX_FILE):
        return
    try:
        with open(LEGACY_HOME_FAVORITES_INDEX_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return
    items = []
    for it in data.get("items") or []:
        rel = (it.get("path") or "").strip()
        if not rel:
            continue
        abs_path = os.path.join(ROOT_DIR, rel)
        new_rel = None
        if rel.startswith("assets/bg-history/") and os.path.exists(abs_path):
            new_rel = rel
        elif os.path.exists(abs_path):
            try:
                hist = _history_path_for_digest(_file_md5(abs_path))
                if hist:
                    new_rel = os.path.relpath(hist, ROOT_DIR)
            except Exception:
                pass
        if not new_rel:
            continue
        fn = os.path.basename(new_rel)
        items.append({
            "id": (it.get("id") or fn.replace(".webp", "")),
            "path": new_rel,
            "created_at": it.get("created_at") or "",
        })
    os.makedirs(BG_HISTORY_DIR, exist_ok=True)
    with open(HOME_FAVORITES_INDEX_FILE, "w", encoding="utf-8") as f:
        json.dump({"items": items}, f, ensure_ascii=False, indent=2)


def _ensure_home_favorites_index():
    os.makedirs(BG_HISTORY_DIR, exist_ok=True)
    _migrate_legacy_home_favorites_index()
    if not os.path.exists(HOME_FAVORITES_INDEX_FILE):
        with open(HOME_FAVORITES_INDEX_FILE, "w", encoding="utf-8") as f:
            json.dump({"items": []}, f, ensure_ascii=False, indent=2)


def _load_home_favorites_index():
    _ensure_home_favorites_index()
    try:
        with open(HOME_FAVORITES_INDEX_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict) and isinstance(data.get("items"), list):
                return data
    except Exception:
        pass
    return {"items": []}


def _save_home_favorites_index(data):
    _ensure_home_favorites_index()
    with open(HOME_FAVORITES_INDEX_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _resolve_bg_history_rel_for_active_room() -> str | None:
    """Return bg-history rel path for the active room; archive once if missing from gallery."""
    target = FRONTEND_PATH / "office_bg_small.webp"
    if not target.exists():
        return None
    existing = _history_path_for_digest(_file_md5(str(target)))
    if existing:
        return os.path.relpath(existing, ROOT_DIR)
    if _should_skip_archive(target):
        return None
    archived = _archive_background_to_history(target, slug=f"saved-{datetime.now().strftime('%Y%m%d-%H%M%S')}")
    return archived


def _maybe_apply_random_home_favorite():
    """On page open, randomly apply one saved home favorite if available."""
    global _last_home_rotate_at

    if not AUTO_ROTATE_HOME_ON_PAGE_OPEN:
        return False, "disabled"

    try:
        now_ts = datetime.now().timestamp()
        if _last_home_rotate_at and (now_ts - _last_home_rotate_at) < AUTO_ROTATE_MIN_INTERVAL_SECONDS:
            return False, "throttled"

        idx = _load_home_favorites_index()
        items = idx.get("items") or []
        candidates = []
        for it in items:
            rel = (it.get("path") or "").strip()
            if not rel:
                continue
            abs_path = os.path.join(ROOT_DIR, rel)
            if os.path.exists(abs_path):
                candidates.append((rel, abs_path))

        if not candidates:
            return False, "no-favorites"

        rel, src = random.choice(candidates)
        target = FRONTEND_PATH / "office_bg_small.webp"
        if not target.exists():
            return False, "missing-office-bg"

        shutil.copy2(src, str(target))
        _last_home_rotate_at = now_ts
        return True, rel
    except Exception as e:
        return False, str(e)


def load_join_keys():
    return _store_load_join_keys(JOIN_KEYS_FILE)


def save_join_keys(data):
    _store_save_join_keys(JOIN_KEYS_FILE, data)


def _ensure_magick_or_ffmpeg_available():
    if shutil.which("magick"):
        return "magick"
    if shutil.which("ffmpeg"):
        return "ffmpeg"
    return None


def _probe_animated_frame_size(upload_path: str):
    """Return (w,h) from first frame if possible."""
    if Image is not None:
        try:
            with Image.open(upload_path) as im:
                w, h = im.size
                return int(w), int(h)
        except Exception:
            pass
    # ffprobe fallback
    if shutil.which("ffprobe"):
        try:
            cmd = [
                "ffprobe", "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height",
                "-of", "csv=p=0:s=x",
                upload_path,
            ]
            out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=5).decode().strip()
            if "x" in out:
                w, h = out.split("x", 1)
                return int(w), int(h)
        except Exception:
            pass
    return None, None


def _animated_to_spritesheet(
    upload_path: str,
    frame_w: int,
    frame_h: int,
    out_ext: str = ".webp",
    preserve_original: bool = True,
    pixel_art: bool = True,
    cols: int | None = None,
    rows: int | None = None,
):
    """Convert animated GIF/WEBP to spritesheet, return (out_path, columns, rows, frames, out_frame_w, out_frame_h)."""
    backend = _ensure_magick_or_ffmpeg_available()
    if not backend:
        raise RuntimeError("ImageMagick or ffmpeg required for animated image conversion")

    ext = (out_ext or ".webp").lower()
    if ext not in {".webp", ".png"}:
        ext = ".webp"

    out_fd, out_path = tempfile.mkstemp(suffix=ext)
    os.close(out_fd)

    with tempfile.TemporaryDirectory() as td:
        frames = 0
        out_fw, out_fh = int(frame_w), int(frame_h)
        if Image is not None:
            try:
                with Image.open(upload_path) as im:
                    n = getattr(im, "n_frames", 1)
                    # 默认保留用户原始帧尺寸（避免先压缩再放大导致像素糊）
                    if preserve_original:
                        out_fw, out_fh = im.size
                    for i in range(n):
                        im.seek(i)
                        fr = im.convert("RGBA")
                        if not preserve_original and (fr.size != (out_fw, out_fh)):
                            resample = Image.Resampling.NEAREST if pixel_art else Image.Resampling.LANCZOS
                            fr = fr.resize((out_fw, out_fh), resample)
                        fr.save(os.path.join(td, f"f_{i:04d}.png"), "PNG")
                    frames = n
            except Exception:
                frames = 0

        if frames <= 0:
            cmd1 = f"ffmpeg -y -i '{upload_path}' '{td}/f_%04d.png' >/dev/null 2>&1"
            if os.system(cmd1) != 0:
                raise RuntimeError("Failed to extract animation frames (Pillow and ffmpeg both failed)")
            files = sorted([x for x in os.listdir(td) if x.startswith("f_") and x.endswith(".png")])
            frames = len(files)
            if frames <= 0:
                raise RuntimeError("Animation has no valid frames")

        if backend == "magick":
            # 像素风动图转精灵表默认无损，避免颜色/边缘被压缩糊掉
            quality_flag = "-define webp:lossless=true -define webp:method=6 -quality 100" if ext == ".webp" else ""
            # 允许按 cols/rows 排布；默认单行
            if cols is None or cols <= 0:
                cols_eff = frames
            else:
                cols_eff = max(1, int(cols))
            rows_eff = max(1, int(rows)) if (rows is not None and rows > 0) else max(1, math.ceil(frames / cols_eff))

            # 先规范单帧尺寸
            prep = ""
            if not preserve_original:
                magick_filter = "-filter point" if pixel_art else ""
                prep = f" {magick_filter} -resize {out_fw}x{out_fh}^ -gravity center -background none -extent {out_fw}x{out_fh}"

            cmd = (
                f"magick '{td}/f_*.png'{prep} "
                f"-tile {cols_eff}x{rows_eff} -background none -geometry +0+0 {quality_flag} '{out_path}'"
            )
            rc = os.system(cmd)
            if rc != 0:
                raise RuntimeError("ImageMagick montage failed")
            return out_path, cols_eff, rows_eff, frames, out_fw, out_fh

        ffmpeg_quality = "-lossless 1 -compression_level 6 -q:v 100" if ext == ".webp" else ""
        cols_eff = max(1, int(cols)) if (cols is not None and cols > 0) else frames
        rows_eff = max(1, int(rows)) if (rows is not None and rows > 0) else max(1, math.ceil(frames / cols_eff))
        if preserve_original:
            vf = f"tile={cols_eff}x{rows_eff}"
        else:
            scale_algo = "neighbor" if pixel_art else "lanczos"
            vf = (
                f"scale={out_fw}:{out_fh}:force_original_aspect_ratio=decrease:flags={scale_algo},"
                f"pad={out_fw}:{out_fh}:(ow-iw)/2:(oh-ih)/2:color=0x00000000,"
                f"tile={cols_eff}x{rows_eff}"
            )
        cmd2 = (
            f"ffmpeg -y -pattern_type glob -i '{td}/f_*.png' "
            f"-vf '{vf}' "
            f"{ffmpeg_quality} '{out_path}' >/dev/null 2>&1"
        )
        if os.system(cmd2) != 0:
            raise RuntimeError("ffmpeg montage failed")
        return out_path, frames, 1, frames, out_fw, out_fh


def normalize_agent_state(s):
    """Normalize agent state for compatibility.
    Maps synonyms (e.g. working/busy -> writing, run/running -> executing) into VALID_AGENT_STATES.
    Returns 'idle' for unknown values.
    """
    if not s:
        return 'idle'
    s_lower = s.lower().strip()
    if s_lower in {'working', 'busy', 'write'}:
        return 'writing'
    if s_lower in {'run', 'running', 'execute', 'exec'}:
        return 'executing'
    if s_lower in {'sync'}:
        return 'syncing'
    if s_lower in {'research', 'search'}:
        return 'researching'
    if s_lower in VALID_AGENT_STATES:
        return s_lower
    return 'idle'


# User-facing model aliases -> provider model ids
USER_MODEL_TO_PROVIDER_MODELS = {
    # 严格按用户要求：仅两种官方模型映射
    "nanobanana-pro": [
        "nano-banana-pro-preview",
    ],
    "nanobanana-2": [
        "gemini-2.5-flash-image",
    ],
}

PROVIDER_MODEL_TO_USER_MODEL = {
    provider: user
    for user, providers in USER_MODEL_TO_PROVIDER_MODELS.items()
    for provider in providers
}


def _normalize_user_model(model_name: str) -> str:
    m = (model_name or "").strip()
    if not m:
        return "nanobanana-pro"
    low = m.lower()
    if low in USER_MODEL_TO_PROVIDER_MODELS:
        return low
    if low in PROVIDER_MODEL_TO_USER_MODEL:
        return PROVIDER_MODEL_TO_USER_MODEL[low]
    return "nanobanana-pro"


def _provider_model_candidates(user_model: str):
    normalized = _normalize_user_model(user_model)
    return list(USER_MODEL_TO_PROVIDER_MODELS.get(normalized, USER_MODEL_TO_PROVIDER_MODELS["nanobanana-pro"]))


def _request_http_referer() -> str:
    """Browser page origin — satisfies API keys locked to HTTP referrers."""
    cfg = load_runtime_config()
    ref = (cfg.get("gemini_http_referer") or "").strip()
    if not ref:
        ref = (request.headers.get("Referer") or request.headers.get("Origin") or "").strip()
    if not ref:
        port = os.environ.get("STAR_BACKEND_PORT", "19000")
        ref = f"http://127.0.0.1:{port}/"
    if ref and not ref.endswith("/"):
        ref += "/"
    return ref


def _generate_rpg_background_to_webp(out_webp_path: str, width: int = 1280, height: int = 720, custom_prompt: str = "", speed_mode: str = "fast", http_referer: str = ""):
    """Generate RPG-style room background and save as webp.

    speed_mode:
      - fast: use nanobanana-2 + 1024x576 intermediate + downscaled reference (faster)
      - quality: use configured model (fallback nanobanana-pro) + full 1280x720 path
    """
    runtime_cfg = load_runtime_config()
    api_key = (runtime_cfg.get("gemini_api_key") or "").strip()
    if not api_key:
        raise RuntimeError("MISSING_API_KEY")
    themes = [
        "8-bit dungeon guild room",
        "8-bit stardew-valley inspired cozy farm tavern",
        "8-bit nordic fantasy tavern",
        "8-bit magitech workshop",
        "8-bit elven forest inn",
        "8-bit pixel cyber tavern",
        "8-bit desert caravan inn",
        "8-bit snow mountain lodge",
    ]
    theme = random.choice(themes)

    if not (os.path.exists(GEMINI_PYTHON) and os.path.exists(GEMINI_SCRIPT)):
        raise RuntimeError(GEMINI_SKILL_MISSING_MSG)

    style_hint = (custom_prompt or "").strip()
    if not style_hint:
        style_hint = theme

    # 默认使用更稳妥的 quality 档，避免 fast 模型在部分 API 通道不可用
    mode = (speed_mode or "quality").strip().lower()
    if mode not in {"fast", "quality"}:
        mode = "quality"

    configured_user_model = _normalize_user_model(runtime_cfg.get("gemini_model") or "nanobanana-pro")
    if mode == "fast":
        preferred_user_model = "nanobanana-2"
        # fast 也提高基础清晰度：从 1024x576 提升到 1152x648（牺牲少量速度）
        gen_width, gen_height = 1152, 648
        ref_width, ref_height = 1152, 648
    else:
        preferred_user_model = configured_user_model
        gen_width, gen_height = width, height
        ref_width, ref_height = width, height

    # 同时规避可能触发 400 的特殊能力参数：
    # 仅 nanobanana-2 走 aspect-ratio，nanobanana-pro 交给模型默认比例（后续再标准化到 1280x720）
    allow_aspect_ratio = (preferred_user_model == "nanobanana-2")

    prompt = build_room_gen_prompt(style_hint)

    tmp_dir = tempfile.mkdtemp(prefix="rpg-bg-")
    cmd = [
        GEMINI_PYTHON,
        GEMINI_SCRIPT,
        "--prompt", prompt,
        "--model", configured_user_model,
        "--out-dir", tmp_dir,
        "--cleanup",
    ]
    if allow_aspect_ratio:
        cmd.extend(["--aspect-ratio", "16:9"])

    # 强约束：每次都带固定参考图，保持房间区域布局不漂移
    ref_for_call = None
    if os.path.exists(ROOM_REFERENCE_IMAGE):
        ref_for_call = ROOM_REFERENCE_IMAGE
        if mode == "fast" and Image is not None:
            try:
                ref_fast = os.path.join(tmp_dir, "room-reference-fast.webp")
                with Image.open(ROOM_REFERENCE_IMAGE) as rim:
                    rim = rim.convert("RGBA").resize((ref_width, ref_height), Image.Resampling.LANCZOS)
                    rim.save(ref_fast, "WEBP", quality=85, method=4)
                ref_for_call = ref_fast
            except Exception:
                ref_for_call = ROOM_REFERENCE_IMAGE

    if ref_for_call:
        cmd.extend(["--reference-image", ref_for_call])

    env = os.environ.copy()
    # 运行时配置优先：只保留 GEMINI_API_KEY，避免脚本因双 key 报错
    env.pop("GOOGLE_API_KEY", None)
    env["GEMINI_API_KEY"] = api_key
    ref = (http_referer or "").strip() or (runtime_cfg.get("gemini_http_referer") or "").strip()
    if ref:
        if not ref.endswith("/"):
            ref += "/"
        env["GEMINI_HTTP_REFERER"] = ref

    def _run_cmd(cmd_args):
        return subprocess.run(cmd_args, capture_output=True, text=True, env=env, timeout=240)

    def _is_model_unavailable_error(text: str) -> bool:
        low = (text or "").strip().lower()
        return (
            ("not found" in low and "models/" in low)
            or ("model_not_available" in low)
            or ("model is not available" in low)
            or ("configured model is not available" in low)
            or ("this model is not available" in low)
            or ("not supported for generatecontent" in low)
        )

    def _with_model(cmd_args, model_name: str):
        m = cmd_args[:]
        if "--model" in m:
            idx = m.index("--model")
            if idx + 1 < len(m):
                m[idx + 1] = model_name
        else:
            m.extend(["--model", model_name])
        return m

    # 模型多级回退（仅允许两类用户模型：nanobanana-pro / nanobanana-2）
    # 每个用户模型映射到若干 provider 真实模型。
    user_model_order = [preferred_user_model, configured_user_model]
    user_model_order = [m for i, m in enumerate(user_model_order) if m and m not in user_model_order[:i]]

    model_candidates = []
    for um in user_model_order:
        model_candidates.extend(_provider_model_candidates(um))
    # 去重并清理空项
    model_candidates = [m for i, m in enumerate(model_candidates) if m and m not in model_candidates[:i]]

    proc = None
    last_err_text = ""
    model_unavailable_count = 0

    for mname in model_candidates:
        env["GEMINI_MODEL"] = mname
        try_cmd = _with_model(cmd, mname)
        proc = _run_cmd(try_cmd)
        if proc.returncode == 0:
            break

        err_text = (proc.stderr or proc.stdout or "").strip()
        last_err_text = err_text

        low = err_text.lower()
        if "your api key was reported as leaked" in low:
            raise RuntimeError("API_KEY_REVOKED_OR_LEAKED")
        if "api_key_http_referrer_blocked" in low or "referer <empty> are blocked" in low:
            raise RuntimeError("API_KEY_REFERRER_BLOCKED")
        if "api_key_invalid" in low or "api key not valid" in low:
            raise RuntimeError("API_KEY_INVALID")

        if _is_model_unavailable_error(err_text):
            model_unavailable_count += 1
            continue

        # 非模型不可用错误，直接返回真实错误
        raise RuntimeError(f"Image generation failed: {err_text}")

    if proc is None or proc.returncode != 0:
        err_text = (last_err_text or "").strip()
        if model_unavailable_count >= len(model_candidates) or _is_model_unavailable_error(err_text):
            brief = (err_text or "").replace("\n", " ")[:240]
            raise RuntimeError(f"MODEL_NOT_AVAILABLE::{brief}")
        raise RuntimeError(f"Image generation failed: {err_text}")

    try:
        result = json.loads(proc.stdout.strip().splitlines()[-1])
    except Exception:
        raise RuntimeError("Failed to parse generation result")

    files = result.get("files") or []
    if not files:
        raise RuntimeError("Generation returned no files")

    gen_path = files[0]
    if not os.path.exists(gen_path):
        raise RuntimeError("Generated file not found")

    if Image is None:
        raise RuntimeError("Pillow required for image resize")

    with Image.open(gen_path) as im:
        im = im.convert("RGBA")
        # 质量模式优先保细节；快速模式优先速度
        if mode == "fast":
            im = im.resize((gen_width, gen_height), Image.Resampling.LANCZOS)
            if (gen_width, gen_height) != (width, height):
                # fast 的放大改为 LANCZOS，牺牲少量速度换更高细节
                im = im.resize((width, height), Image.Resampling.LANCZOS)
            im.save(out_webp_path, "WEBP", quality=96, method=6)
        else:
            # quality：确保输出标准尺寸，同时使用无损 webp，减少压缩损失
            if im.size != (width, height):
                im = im.resize((width, height), Image.Resampling.LANCZOS)
            im.save(out_webp_path, "WEBP", lossless=True, quality=100, method=6)

    return style_hint


def state_to_area(state):
    """Map agent state to office area (center_room / cat_room / error)."""
    return STATE_TO_AREA_MAP.get(state, "center_room")


# Ensure files exist
if not os.path.exists(AGENTS_STATE_FILE):
    save_agents_state(DEFAULT_AGENTS)
if not os.path.exists(JOIN_KEYS_FILE):
    if os.path.exists(os.path.join(ROOT_DIR, "join-keys.sample.json")):
        try:
            with open(os.path.join(ROOT_DIR, "join-keys.sample.json"), "r", encoding="utf-8") as sf:
                sample = json.load(sf)
            save_join_keys(sample if isinstance(sample, dict) else {"keys": []})
        except Exception:
            save_join_keys({"keys": []})
    else:
        save_join_keys({"keys": []})

# Tighten runtime-config file perms if exists
if os.path.exists(RUNTIME_CONFIG_FILE):
    try:
        os.chmod(RUNTIME_CONFIG_FILE, 0o600)
    except Exception:
        pass


@app.route("/agents", methods=["GET"])
def get_agents():
    """Get full agents list (for multi-agent UI), with auto-cleanup on access"""
    agents = load_agents_state()
    now = datetime.now()

    cleaned_agents = []
    keys_data = load_join_keys()

    for a in agents:
        if a.get("isMain"):
            cleaned_agents.append(a)
            continue

        auth_expires_at_str = a.get("authExpiresAt")
        auth_status = a.get("authStatus", "pending")

        # 1) 超时未批准自动 leave
        if auth_status == "pending" and auth_expires_at_str:
            try:
                auth_expires_at = datetime.fromisoformat(auth_expires_at_str)
                if now > auth_expires_at:
                    key = a.get("joinKey")
                    if key:
                        key_item = next((k for k in keys_data.get("keys", []) if k.get("key") == key), None)
                        if key_item:
                            key_item["used"] = False
                            key_item["usedBy"] = None
                            key_item["usedByAgentId"] = None
                            key_item["usedAt"] = None
                    continue
            except Exception:
                pass

        # 2) 超时未推送自动离线（超过5分钟）
        last_push_at_str = a.get("lastPushAt")
        if auth_status == "approved" and last_push_at_str:
            try:
                last_push_at = datetime.fromisoformat(last_push_at_str)
                age = (now - last_push_at).total_seconds()
                if age > 300:  # 5分钟无推送自动离线
                    a["authStatus"] = "offline"
            except Exception:
                pass

        cleaned_agents.append(a)

    save_agents_state(cleaned_agents)
    save_join_keys(keys_data)

    return jsonify(cleaned_agents)


@app.route("/agent-approve", methods=["POST"])
def agent_approve():
    """Approve an agent (set authStatus to approved)"""
    try:
        data = request.get_json()
        agent_id = (data.get("agentId") or "").strip()
        if not agent_id:
            return jsonify({"ok": False, "msg": "missing agentId"}), 400

        agents = load_agents_state()
        target = next((a for a in agents if a.get("agentId") == agent_id and not a.get("isMain")), None)
        if not target:
            return jsonify({"ok": False, "msg": "agent not found"}), 404

        target["authStatus"] = "approved"
        target["authApprovedAt"] = datetime.now().isoformat()
        target["authExpiresAt"] = (datetime.now() + timedelta(hours=24)).isoformat()  # 默认授权24h

        save_agents_state(agents)
        return jsonify({"ok": True, "agentId": agent_id, "authStatus": "approved"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/agent-reject", methods=["POST"])
def agent_reject():
    """Reject an agent (set authStatus to rejected and optionally revoke key)"""
    try:
        data = request.get_json()
        agent_id = (data.get("agentId") or "").strip()
        if not agent_id:
            return jsonify({"ok": False, "msg": "missing agentId"}), 400

        agents = load_agents_state()
        target = next((a for a in agents if a.get("agentId") == agent_id and not a.get("isMain")), None)
        if not target:
            return jsonify({"ok": False, "msg": "agent not found"}), 404

        target["authStatus"] = "rejected"
        target["authRejectedAt"] = datetime.now().isoformat()

        # Optionally free join key back to unused
        join_key = target.get("joinKey")
        keys_data = load_join_keys()
        if join_key:
            key_item = next((k for k in keys_data.get("keys", []) if k.get("key") == join_key), None)
            if key_item:
                key_item["used"] = False
                key_item["usedBy"] = None
                key_item["usedByAgentId"] = None
                key_item["usedAt"] = None

        # Remove from agents list
        agents = [a for a in agents if a.get("agentId") != agent_id or a.get("isMain")]

        save_agents_state(agents)
        save_join_keys(keys_data)
        return jsonify({"ok": True, "agentId": agent_id, "authStatus": "rejected"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/join-agent", methods=["POST"])
def join_agent():
    """Add a new agent with one-time join key validation and pending auth"""
    try:
        data = request.get_json()
        if not isinstance(data, dict) or not data.get("name"):
            return jsonify({"ok": False, "msg": "name required"}), 400

        name = data["name"].strip()
        state = data.get("state", "idle")
        detail = data.get("detail", "")
        join_key = data.get("joinKey", "").strip()

        # Normalize state early for compatibility
        state = normalize_agent_state(state)

        if not join_key:
            return jsonify({"ok": False, "msg": "join key required"}), 400

        keys_data = load_join_keys()
        key_item = next((k for k in keys_data.get("keys", []) if k.get("key") == join_key), None)
        if not key_item:
            return jsonify({"ok": False, "msg": "invalid join key"}), 403
        # key 可复用：不再因为 used=true 拒绝

        with join_lock:
            # 在锁内重新读取，避免并发请求都基于同一旧快照通过校验
            keys_data = load_join_keys()
            key_item = next((k for k in keys_data.get("keys", []) if k.get("key") == join_key), None)
            if not key_item:
                return jsonify({"ok": False, "msg": "invalid join key"}), 403

            # Key-level expiration check
            key_expires_at_str = key_item.get("expiresAt")
            if key_expires_at_str:
                try:
                    key_expires_at = datetime.fromisoformat(key_expires_at_str)
                    if datetime.now() > key_expires_at:
                        return jsonify({"ok": False, "msg": "join key expired — event ended 🎉"}), 403
                except Exception:
                    pass

            agents = load_agents_state()

            # 并发上限：同一个 key “同时在线”最多 3 个。
            # 在线判定：lastPushAt/updated_at 在 5 分钟内；否则视为 offline，不计入并发。
            now = datetime.now()
            existing = next((a for a in agents if a.get("name") == name and not a.get("isMain")), None)
            existing_id = existing.get("agentId") if existing else None

            def _age_seconds(dt_str):
                if not dt_str:
                    return None
                try:
                    dt = datetime.fromisoformat(dt_str)
                    return (now - dt).total_seconds()
                except Exception:
                    return None

            # opportunistic offline marking
            for a in agents:
                if a.get("isMain"):
                    continue
                if a.get("authStatus") != "approved":
                    continue
                age = _age_seconds(a.get("lastPushAt"))
                if age is None:
                    age = _age_seconds(a.get("updated_at"))
                if age is not None and age > 300:
                    a["authStatus"] = "offline"

            max_concurrent = int(key_item.get("maxConcurrent", 3))
            active_count = 0
            for a in agents:
                if a.get("isMain"):
                    continue
                if a.get("agentId") == existing_id:
                    continue
                if a.get("joinKey") != join_key:
                    continue
                if a.get("authStatus") != "approved":
                    continue
                age = _age_seconds(a.get("lastPushAt"))
                if age is None:
                    age = _age_seconds(a.get("updated_at"))
                if age is None or age <= 300:
                    active_count += 1

            if active_count >= max_concurrent:
                save_agents_state(agents)
                return jsonify({"ok": False, "msg": f"join key concurrent limit reached ({max_concurrent}) — try later or use another key"}), 429

            if existing:
                existing["state"] = state
                existing["detail"] = detail
                existing["updated_at"] = datetime.now().isoformat()
                existing["area"] = state_to_area(state)
                existing["source"] = "remote-openclaw"
                existing["joinKey"] = join_key
                existing["authStatus"] = "approved"
                existing["authApprovedAt"] = datetime.now().isoformat()
                existing["authExpiresAt"] = (datetime.now() + timedelta(hours=24)).isoformat()
                existing["lastPushAt"] = datetime.now().isoformat()  # join 视为上线，纳入并发/离线判定
                if not existing.get("avatar"):
                    import random
                    existing["avatar"] = random.choice(GUEST_AVATARS)
                agent_id = existing.get("agentId")
            else:
                # Use ms + random suffix to avoid collisions under concurrent joins
                import random
                import string
                agent_id = "agent_" + str(int(datetime.now().timestamp() * 1000)) + "_" + "".join(random.choices(string.ascii_lowercase + string.digits, k=4))
                agents.append({
                    "agentId": agent_id,
                    "name": name,
                    "isMain": False,
                    "state": state,
                    "detail": detail,
                    "updated_at": datetime.now().isoformat(),
                    "area": state_to_area(state),
                    "source": "remote-openclaw",
                    "joinKey": join_key,
                    "authStatus": "approved",
                    "authApprovedAt": datetime.now().isoformat(),
                    "authExpiresAt": (datetime.now() + timedelta(hours=24)).isoformat(),
                    "lastPushAt": datetime.now().isoformat(),
                    "avatar": random.choice(GUEST_AVATARS)
                })

            key_item["used"] = True
            key_item["usedBy"] = name
            key_item["usedByAgentId"] = agent_id
            key_item["usedAt"] = datetime.now().isoformat()
            key_item["reusable"] = True

            # 拿到有效 key 直接批准，不再等待主人手动点击
            # （状态已在上面 existing/new 分支写入）
            save_agents_state(agents)
            save_join_keys(keys_data)

        return jsonify({"ok": True, "agentId": agent_id, "authStatus": "approved", "nextStep": "Auto-approved — start pushing status"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/leave-agent", methods=["POST"])
def leave_agent():
    """Remove an agent and free its one-time join key for reuse (optional)

    Prefer agentId (stable). Name is accepted for backward compatibility.
    """
    try:
        data = request.get_json()
        if not isinstance(data, dict):
            return jsonify({"ok": False, "msg": "invalid json"}), 400

        agent_id = (data.get("agentId") or "").strip()
        name = (data.get("name") or "").strip()
        if not agent_id and not name:
            return jsonify({"ok": False, "msg": "agentId or name required"}), 400

        agents = load_agents_state()

        target = None
        if agent_id:
            target = next((a for a in agents if a.get("agentId") == agent_id and not a.get("isMain")), None)
        if (not target) and name:
            # fallback: remove by name only if agentId not provided
            target = next((a for a in agents if a.get("name") == name and not a.get("isMain")), None)

        if not target:
            return jsonify({"ok": False, "msg": "no agent found to remove"}), 404

        join_key = target.get("joinKey")
        new_agents = [a for a in agents if a.get("isMain") or a.get("agentId") != target.get("agentId")]

        # Optional: free key back to unused after leave
        keys_data = load_join_keys()
        if join_key:
            key_item = next((k for k in keys_data.get("keys", []) if k.get("key") == join_key), None)
            if key_item:
                key_item["used"] = False
                key_item["usedBy"] = None
                key_item["usedByAgentId"] = None
                key_item["usedAt"] = None

        save_agents_state(new_agents)
        save_join_keys(keys_data)
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/status", methods=["GET"])
def get_status():
    """Get current main state (backward compatibility). Optionally include officeName from IDENTITY.md."""
    state = load_state()
    office_name = get_office_name_from_identity()
    if office_name:
        state["officeName"] = office_name
    return jsonify(state)


@app.route("/activity", methods=["GET"])
def get_activity():
    """Loop activity feed mirrored from status.json by star-office-bridge.js."""
    path = os.path.join(ROOT_DIR, "activity.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            return jsonify(json.load(f))
    except FileNotFoundError:
        return jsonify({"log": [], "project": "", "task": "", "loop": 1, "updatedAt": None})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e), "log": []}), 500


@app.route("/activity/clear", methods=["POST"])
def clear_activity():
    """Archive status.json log to log-archive/ and clear the live feed."""
    try:
        if not os.path.isfile(AGENT_STATUS_JS):
            return jsonify({"ok": False, "msg": "agent-status.js not found"}), 500
        result = subprocess.run(
            ["node", AGENT_STATUS_JS, "clearlog"],
            capture_output=True,
            text=True,
            timeout=15,
            cwd=DASH_DIR,
        )
        if result.returncode != 0:
            msg = (result.stderr or result.stdout or "clearlog failed").strip()
            return jsonify({"ok": False, "msg": msg}), 500
        stdout = (result.stdout or "").strip()
        archive = None
        msg = stdout
        for line in reversed(stdout.splitlines()):
            if line.startswith("ARCHIVE:"):
                try:
                    archive = json.loads(line[8:])
                except json.JSONDecodeError:
                    pass
            elif line.startswith("log cleared"):
                msg = line
        return jsonify({"ok": True, "msg": msg, "archive": archive})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/activity/archives", methods=["GET"])
def list_activity_archives():
    """List daily log archives in log-archive/."""
    try:
        if not os.path.isdir(ARCHIVE_DIR):
            return jsonify({"archives": []})
        archives = []
        for name in sorted(os.listdir(ARCHIVE_DIR), reverse=True):
            if not ARCHIVE_NAME_RE.match(name):
                continue
            path = os.path.join(ARCHIVE_DIR, name)
            count = 0
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                count = len(data) if isinstance(data, list) else 0
            except Exception:
                pass
            archives.append({
                "id": name,
                "date": name[len("status-"):-len(".json")],
                "count": count,
            })
        return jsonify({"archives": archives})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e), "archives": []}), 500


@app.route("/activity/archive/<name>", methods=["GET"])
def get_activity_archive(name):
    """Return one archived log file (read-only)."""
    if not ARCHIVE_NAME_RE.match(name):
        return jsonify({"ok": False, "msg": "invalid archive name", "log": []}), 400
    path = os.path.join(ARCHIVE_DIR, name)
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        log = data if isinstance(data, list) else []
        return jsonify({
            "archive": name,
            "date": name[len("status-"):-len(".json")],
            "count": len(log),
            "log": log,
            "updatedAt": None,
        })
    except FileNotFoundError:
        return jsonify({"ok": False, "msg": "not found", "log": []}), 404
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e), "log": []}), 500


@app.route("/agent-push", methods=["POST"])
def agent_push():
    """Remote openclaw actively pushes status to office.

    Required fields:
    - agentId
    - joinKey
    - state
    Optional:
    - detail
    - name
    """
    try:
        data = request.get_json()
        if not isinstance(data, dict):
            return jsonify({"ok": False, "msg": "invalid json"}), 400

        agent_id = (data.get("agentId") or "").strip()
        join_key = (data.get("joinKey") or "").strip()
        state = (data.get("state") or "").strip()
        detail = (data.get("detail") or "").strip()
        name = (data.get("name") or "").strip()

        if not agent_id or not join_key or not state:
            return jsonify({"ok": False, "msg": "missing agentId/joinKey/state"}), 400

        state = normalize_agent_state(state)

        keys_data = load_join_keys()
        key_item = next((k for k in keys_data.get("keys", []) if k.get("key") == join_key), None)
        if not key_item:
            return jsonify({"ok": False, "msg": "invalid joinKey"}), 403

        # Key-level expiration check
        key_expires_at_str = key_item.get("expiresAt")
        if key_expires_at_str:
            try:
                key_expires_at = datetime.fromisoformat(key_expires_at_str)
                if datetime.now() > key_expires_at:
                    return jsonify({"ok": False, "msg": "join key expired — event ended 🎉"}), 403
            except Exception:
                pass


        agents = load_agents_state()
        target = next((a for a in agents if a.get("agentId") == agent_id and not a.get("isMain")), None)
        if not target:
            return jsonify({"ok": False, "msg": "agent not registered — join first"}), 404

        # Auth check: only approved agents can push.
        # Note: "offline" is a presence state (stale), not a revoked authorization.
        # Allow offline agents to resume pushing and auto-promote them back to approved.
        auth_status = target.get("authStatus", "pending")
        if auth_status not in {"approved", "offline"}:
            return jsonify({"ok": False, "msg": "agent not authorized — wait for approval"}), 403
        if auth_status == "offline":
            target["authStatus"] = "approved"
            target["authApprovedAt"] = datetime.now().isoformat()
            target["authExpiresAt"] = (datetime.now() + timedelta(hours=24)).isoformat()

        if target.get("joinKey") != join_key:
            return jsonify({"ok": False, "msg": "joinKey mismatch"}), 403

        target["state"] = state
        target["detail"] = detail
        if name:
            target["name"] = name
        target["updated_at"] = datetime.now().isoformat()
        target["area"] = state_to_area(state)
        target["source"] = "remote-openclaw"
        target["lastPushAt"] = datetime.now().isoformat()

        save_agents_state(agents)
        return jsonify({"ok": True, "agentId": agent_id, "area": target.get("area")})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/health", methods=["GET"])
def health():
    """Health check"""
    return jsonify({
        "status": "ok",
        "service": "star-office-ui",
        "timestamp": datetime.now().isoformat(),
    })


@app.route("/yesterday-memo", methods=["GET"])
def get_yesterday_memo():
    """获取昨日小日记"""
    try:
        # 先尝试找昨天的文件
        yesterday_str = get_yesterday_date_str()
        yesterday_file = os.path.join(MEMORY_DIR, f"{yesterday_str}.md")
        
        target_file = None
        target_date = yesterday_str
        
        if os.path.exists(yesterday_file):
            target_file = yesterday_file
        else:
            # 如果昨天没有，找最近的一天
            if os.path.exists(MEMORY_DIR):
                files = [f for f in os.listdir(MEMORY_DIR) if f.endswith(".md") and re.match(r"\d{4}-\d{2}-\d{2}\.md", f)]
                if files:
                    files.sort(reverse=True)
                    # 跳过今天的（如果存在）
                    today_str = datetime.now().strftime("%Y-%m-%d")
                    for f in files:
                        if f != f"{today_str}.md":
                            target_file = os.path.join(MEMORY_DIR, f)
                            target_date = f.replace(".md", "")
                            break
        
        if target_file and os.path.exists(target_file):
            memo_content = extract_memo_from_file(target_file)
            return jsonify({
                "success": True,
                "date": target_date,
                "memo": memo_content
            })
        else:
            return jsonify({
                "success": False,
                "msg": "No memo found for yesterday"
            })
    except Exception as e:
        return jsonify({
            "success": False,
            "msg": str(e)
        }), 500


@app.route("/set_state", methods=["POST"])
def set_state_endpoint():
    """Set state via POST (for UI control panel)"""
    try:
        data = request.get_json()
        if not isinstance(data, dict):
            return jsonify({"status": "error", "msg": "invalid json"}), 400
        state = load_state()
        if "state" in data:
            s = data["state"]
            if s in VALID_AGENT_STATES:
                state["state"] = s
        if "detail" in data:
            state["detail"] = data["detail"]
        state["updated_at"] = datetime.now().isoformat()
        save_state(state)
        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)}), 500


@app.route("/assets/template.zip", methods=["GET"])
def assets_template_download():
    if not os.path.exists(ASSET_TEMPLATE_ZIP):
        return jsonify({"ok": False, "msg": "template package not found — generate it first"}), 404
    return send_from_directory(ROOT_DIR, "assets-replace-template.zip", as_attachment=True)


@app.route("/assets/list", methods=["GET"])
def assets_list():
    items = []
    for p in FRONTEND_PATH.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(FRONTEND_PATH).as_posix()
        if rel.startswith("fonts/"):
            continue
        # Dev/scratch files (e.g. _tmp-coffee-0.png) are not DIY assets
        name = p.name.lower()
        if name.startswith("_") or name.startswith("."):
            continue
        if name.endswith(".bak") or name.endswith(".default") or name.endswith(".tmp"):
            continue
        if p.suffix.lower() not in ASSET_ALLOWED_EXTS:
            continue
        st = p.stat()
        width = None
        height = None
        if Image is not None:
            try:
                with Image.open(p) as im:
                    width, height = im.size
            except Exception:
                pass
        items.append({
            "path": rel,
            "size": st.st_size,
            "ext": p.suffix.lower(),
            "width": width,
            "height": height,
            "mtime": datetime.fromtimestamp(st.st_mtime).isoformat(),
        })
    items.sort(key=lambda x: x["path"])
    return jsonify({"ok": True, "count": len(items), "items": items})


def _slugify_room_name(text: str, fallback: str = "room") -> str:
    s = re.sub(r"[^a-z0-9]+", "-", (text or "").lower().strip())
    s = s.strip("-")[:48]
    return s or fallback


def _unique_history_filepath(slug: str) -> str:
    os.makedirs(BG_HISTORY_DIR, exist_ok=True)
    safe = _slugify_room_name(slug)
    base = f"{BG_HISTORY_PREFIX}{safe}"
    path = os.path.join(BG_HISTORY_DIR, f"{base}.webp")
    if not os.path.exists(path):
        return path
    n = 2
    while True:
        path = os.path.join(BG_HISTORY_DIR, f"{base}-{n}.webp")
        if not os.path.exists(path):
            return path
        n += 1


def _history_path_for_digest(digest: str) -> str | None:
    if not digest or not os.path.isdir(BG_HISTORY_DIR):
        return None
    for fn in os.listdir(BG_HISTORY_DIR):
        if not _safe_history_filename(fn):
            continue
        path = os.path.join(BG_HISTORY_DIR, fn)
        try:
            if _file_md5(path) == digest:
                return path
        except Exception:
            continue
    return None


def _should_skip_archive(path: Path) -> bool:
    """Skip gallery copy when active room already exists in history or is factory default."""
    if not path.exists():
        return True
    digest = _file_md5(str(path))
    if _history_path_for_digest(digest):
        return True
    ref_digest = _reference_normalized_digest()
    return bool(ref_digest and digest == ref_digest)


def _archive_background_to_history(target: Path, *, slug: str | None = None) -> str | None:
    """Copy current active background into bg-history before it is replaced."""
    if _should_skip_archive(target):
        return None
    name = slug or f"archived-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    hist_file = _unique_history_filepath(name)
    shutil.copy2(target, hist_file)
    return os.path.relpath(hist_file, ROOT_DIR)


def _save_generated_to_history(target: Path, style_label: str, custom_prompt: str) -> str | None:
    """Register a freshly generated room in the gallery under a unique slug."""
    if not target.exists():
        return None
    digest = _file_md5(str(target))
    existing = _history_path_for_digest(digest)
    if existing:
        return os.path.relpath(existing, ROOT_DIR)
    slug = _slugify_room_name(custom_prompt, "custom-style") if (custom_prompt or "").strip() else _slugify_room_name(style_label, "new-home")
    hist_file = _unique_history_filepath(slug)
    shutil.copy2(target, hist_file)
    return os.path.relpath(hist_file, ROOT_DIR)


def _file_md5(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _safe_history_filename(name: str) -> str | None:
    base = os.path.basename((name or "").strip())
    if not base or base != (name or "").strip():
        return None
    if base == "office_bg_small.webp":
        return None
    if base.endswith(".webp") and (
        base.startswith(BG_HISTORY_PREFIX) or base.startswith("office_bg_small-")
    ):
        return base
    return None


def _history_label_from_filename(fn: str) -> str:
    label = fn
    if label.startswith("office_bg_small-"):
        label = label[len("office_bg_small-"):]
    elif label.startswith(BG_HISTORY_PREFIX):
        label = label[len(BG_HISTORY_PREFIX):]
    return label.replace(".webp", "")


def _safe_public_gallery_filename(name: str) -> str | None:
    base = os.path.basename((name or "").strip())
    if not base or base != (name or "").strip():
        return None
    if base in {"manifest.json", "index.json", ".gitkeep"}:
        return None
    ext = os.path.splitext(base)[1].lower()
    if ext not in ROOM_GALLERY_PUBLIC_EXTS:
        return None
    return base


def _public_gallery_label(fn: str, labels: dict[str, str]) -> str:
    if labels.get(fn):
        return labels[fn]
    stem = os.path.splitext(fn)[0]
    return stem.replace("-", " ").replace("_", " ").strip() or fn


def _load_public_gallery_manifest() -> tuple[list[str], dict[str, str]]:
    order: list[str] = []
    labels: dict[str, str] = {}
    if not os.path.exists(ROOM_GALLERY_MANIFEST_FILE):
        return order, labels
    try:
        with open(ROOM_GALLERY_MANIFEST_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        for it in data.get("items") or []:
            if not isinstance(it, dict):
                continue
            fn = _safe_public_gallery_filename((it.get("file") or "").strip())
            if not fn:
                continue
            order.append(fn)
            label = (it.get("label") or "").strip()
            if label:
                labels[fn] = label
    except Exception:
        pass
    return order, labels


def _list_public_gallery_items() -> list[dict]:
    os.makedirs(ROOM_GALLERY_PUBLIC_DIR, exist_ok=True)
    manifest_order, labels = _load_public_gallery_manifest()
    if manifest_order:
        files = [
            fn for fn in manifest_order
            if os.path.isfile(os.path.join(ROOM_GALLERY_PUBLIC_DIR, fn))
        ]
    else:
        files = sorted(
            x for x in os.listdir(ROOM_GALLERY_PUBLIC_DIR)
            if _safe_public_gallery_filename(x)
        )
    items = []
    for fn in files:
        abs_path = os.path.join(ROOM_GALLERY_PUBLIC_DIR, fn)
        items.append({
            "id": f"public:{fn}",
            "kind": "public",
            "label": _public_gallery_label(fn, labels),
            "thumb_url": f"/assets/room-gallery/file/{fn}",
            "created_at": "",
            "digest": _file_md5(abs_path),
            "is_active": False,
        })
    return items


def _reference_normalized_digest() -> str | None:
    if not os.path.exists(ROOM_REFERENCE_IMAGE) or Image is None:
        return None
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".webp", delete=False) as tmp:
            tmp_path = tmp.name
        with Image.open(ROOM_REFERENCE_IMAGE) as im:
            im = im.convert("RGBA").resize((1280, 720), Image.Resampling.LANCZOS)
            im.save(tmp_path, "WEBP", quality=92, method=6)
        return _file_md5(tmp_path)
    except Exception:
        return None
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass


def _activate_background_from_path(src_abs: str, *, archive_current: bool = True, from_reference: bool = False) -> dict:
    """Swap active room background without generating a new image."""
    target = FRONTEND_PATH / "office_bg_small.webp"
    if not os.path.exists(src_abs):
        raise FileNotFoundError(f"source not found: {src_abs}")

    archived = None
    if archive_current and target.exists():
        archived = _archive_background_to_history(target)
        shutil.copy2(target, target.with_suffix(target.suffix + ".bak"))

    if from_reference:
        ref_ext = os.path.splitext(src_abs)[1].lower()
        fast_copied = False
        if ref_ext == ".webp":
            try:
                with Image.open(src_abs) as rim:
                    if rim.size == (1280, 720):
                        shutil.copy2(src_abs, target)
                        fast_copied = True
            except Exception:
                fast_copied = False
        if not fast_copied:
            if Image is None:
                raise RuntimeError("Pillow is not installed — run: pip install pillow (in star-office/.venv)")
            with Image.open(src_abs) as im:
                im = im.convert("RGBA").resize((1280, 720), Image.Resampling.LANCZOS)
                im.save(target, "WEBP", quality=92, method=6)
    else:
        shutil.copy2(src_abs, target)

    st = target.stat()
    return {
        "archived": archived,
        "size": st.st_size,
        "from": os.path.relpath(src_abs, ROOT_DIR) if src_abs.startswith(ROOT_DIR) else src_abs,
    }


def _list_room_background_items():
    target = FRONTEND_PATH / "office_bg_small.webp"
    active_md5 = _file_md5(str(target)) if target.exists() else None
    ref_digest = _reference_normalized_digest()
    items = []
    active_id = None

    if os.path.exists(ROOM_REFERENCE_IMAGE):
        items.append({
            "id": "__default__",
            "kind": "default",
            "label": "Factory Default",
            "thumb_url": "/assets/room-backgrounds/thumb/__default__",
            "created_at": "",
            "digest": ref_digest,
            "is_active": False,
        })

    items.extend(_list_public_gallery_items())

    if os.path.isdir(BG_HISTORY_DIR):
        files = [x for x in os.listdir(BG_HISTORY_DIR) if _safe_history_filename(x)]
        files.sort(key=lambda x: os.path.getmtime(os.path.join(BG_HISTORY_DIR, x)), reverse=True)
        for fn in files:
            abs_path = os.path.join(BG_HISTORY_DIR, fn)
            digest = _file_md5(abs_path)
            items.append({
                "id": fn,
                "kind": "history",
                "label": _history_label_from_filename(fn),
                "thumb_url": f"/assets/bg-history/file/{fn}",
                "created_at": datetime.fromtimestamp(os.path.getmtime(abs_path)).isoformat(timespec="seconds"),
                "digest": digest,
                "is_active": False,
            })

    if active_md5:
        for it in items:
            if it.get("digest") and it["digest"] == active_md5:
                it["is_active"] = True
                active_id = it["id"]
                break

    return items, active_id


def _bg_generate_worker(task_id: str, custom_prompt: str, speed_mode: str, http_referer: str = ""):
    """Background worker for RPG background generation."""
    try:
        target = FRONTEND_PATH / "office_bg_small.webp"

        # Archive + quick backup before overwrite (history keeps every previous room)
        archived = _archive_background_to_history(target)
        bak = target.with_suffix(target.suffix + ".bak")
        shutil.copy2(target, bak)

        style_label = _generate_rpg_background_to_webp(
            str(target),
            width=1280,
            height=720,
            custom_prompt=custom_prompt,
            speed_mode=speed_mode,
            http_referer=http_referer,
        )

        saved = _save_generated_to_history(target, style_label, custom_prompt)

        st = target.stat()
        with _bg_tasks_lock:
            _bg_tasks[task_id] = {
                "status": "done",
                "result": {
                    "ok": True,
                    "path": "office_bg_small.webp",
                    "size": st.st_size,
                    "archived": archived,
                    "saved": saved,
                    "speed_mode": speed_mode,
                    "msg": "Room background generated and added to gallery",
                },
            }
    except Exception as e:
        msg = str(e)
        error_result = {"ok": False, "msg": msg}
        if msg == "MISSING_API_KEY":
            error_result["code"] = "MISSING_API_KEY"
            error_result["msg"] = "Missing GEMINI_API_KEY or GOOGLE_API_KEY"
        elif msg == "API_KEY_REVOKED_OR_LEAKED":
            error_result["code"] = "API_KEY_REVOKED_OR_LEAKED"
            error_result["msg"] = "API key is revoked or flagged as leaked. Please rotate to a new key."
        elif msg == "API_KEY_REFERRER_BLOCKED":
            error_result["code"] = "API_KEY_REFERRER_BLOCKED"
            error_result["msg"] = (
                "API key is restricted to HTTP referrers (browser only). "
                "In Google Cloud Console → Credentials → your key → set Application restrictions to None or IP addresses, then retry."
            )
        elif msg == "API_KEY_INVALID":
            error_result["code"] = "API_KEY_INVALID"
            error_result["msg"] = "API key is invalid. Create a new key in Google AI Studio and save it in the drawer."
        elif msg.startswith("MODEL_NOT_AVAILABLE"):
            error_result["code"] = "MODEL_NOT_AVAILABLE"
            error_result["msg"] = "Configured model is not available for this API key/channel."
            if "::" in msg:
                error_result["detail"] = msg.split("::", 1)[1]
        elif msg == GEMINI_SKILL_MISSING_MSG or "gemini-image-generate" in msg:
            error_result["code"] = "GEMINI_SKILL_MISSING"
            error_result["msg"] = GEMINI_SKILL_MISSING_MSG
        with _bg_tasks_lock:
            _bg_tasks[task_id] = {"status": "error", "result": error_result}


def _apply_generated_image_bytes(image_bytes: bytes, style_label: str, custom_prompt: str) -> dict:
    target = FRONTEND_PATH / "office_bg_small.webp"
    if not target.exists():
        raise FileNotFoundError("office_bg_small.webp not found")

    archived = _archive_background_to_history(target)
    shutil.copy2(target, target.with_suffix(target.suffix + ".bak"))

    if Image is None:
        raise RuntimeError("Pillow is not installed — run: pip install pillow (in star-office/.venv)")

    import io
    with Image.open(io.BytesIO(image_bytes)) as im:
        im = im.convert("RGBA").resize((1280, 720), Image.Resampling.LANCZOS)
        im.save(target, "WEBP", quality=96, method=6)

    saved = _save_generated_to_history(target, style_label, custom_prompt)
    st = target.stat()
    return {"archived": archived, "saved": saved, "size": st.st_size}


@app.route("/assets/apply-generated-image", methods=["POST"])
def assets_apply_generated_image():
    """Save browser-generated image (referrer-safe path) to active room + gallery."""
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        image_b64 = (data.get("image_b64") or "").strip()
        if not image_b64:
            return jsonify({"ok": False, "msg": "missing image_b64"}), 400
        custom_prompt = (data.get("custom_prompt") or "").strip()
        style_label = (data.get("style_label") or custom_prompt or "generated").strip()
        try:
            raw = base64.b64decode(image_b64, validate=True)
        except Exception:
            return jsonify({"ok": False, "msg": "invalid image_b64"}), 400
        if len(raw) < 64:
            return jsonify({"ok": False, "msg": "image payload too small"}), 400

        result = _apply_generated_image_bytes(raw, style_label, custom_prompt)
        return jsonify({
            "ok": True,
            "path": "office_bg_small.webp",
            "size": result["size"],
            "archived": result.get("archived"),
            "saved": result.get("saved"),
            "msg": "Room background applied from browser generation",
        })
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/generate-rpg-background", methods=["POST"])
def assets_generate_rpg_background():
    """Start async RPG background generation. Returns a task_id for polling."""
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        req = request.get_json(silent=True) or {}
        custom_prompt = (req.get("prompt") or "").strip() if isinstance(req, dict) else ""
        speed_mode = (req.get("speed_mode") or "quality").strip().lower() if isinstance(req, dict) else "quality"
        if speed_mode not in {"fast", "quality"}:
            speed_mode = "fast"

        target = FRONTEND_PATH / "office_bg_small.webp"
        if not target.exists():
            return jsonify({"ok": False, "msg": "office_bg_small.webp not found"}), 404

        # Pre-flight checks that can fail fast (before spawning thread)
        runtime_cfg = load_runtime_config()
        api_key = (runtime_cfg.get("gemini_api_key") or "").strip()
        if not api_key:
            return jsonify({"ok": False, "code": "MISSING_API_KEY", "msg": "Missing GEMINI_API_KEY or GOOGLE_API_KEY"}), 400
        if not (os.path.exists(GEMINI_PYTHON) and os.path.exists(GEMINI_SCRIPT)):
            return jsonify({"ok": False, "msg": GEMINI_SKILL_MISSING_MSG}), 500

        # Check if another generation is already running
        with _bg_tasks_lock:
            for tid, task in _bg_tasks.items():
                if task.get("status") == "pending":
                    return jsonify({"ok": True, "async": True, "task_id": tid, "msg": "Generation already in progress — please wait"}), 200

        # Create async task
        import string as _string
        task_id = "gen_" + str(int(datetime.now().timestamp() * 1000)) + "_" + "".join(random.choices(_string.ascii_lowercase + _string.digits, k=4))
        with _bg_tasks_lock:
            _bg_tasks[task_id] = {"status": "pending", "created_at": datetime.now().isoformat()}

        t = threading.Thread(
            target=_bg_generate_worker,
            args=(task_id, custom_prompt, speed_mode, _request_http_referer()),
            daemon=True,
        )
        t.start()

        return jsonify({"ok": True, "async": True, "task_id": task_id, "msg": "Generation started — poll with task_id"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/generate-rpg-background/poll", methods=["GET"])
def assets_generate_rpg_background_poll():
    """Poll async generation task status."""
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    task_id = (request.args.get("task_id") or "").strip()
    if not task_id:
        return jsonify({"ok": False, "msg": "missing task_id"}), 400
    with _bg_tasks_lock:
        task = _bg_tasks.get(task_id)
    if not task:
        return jsonify({"ok": False, "msg": "task not found"}), 404
    status = task.get("status", "pending")
    if status == "pending":
        return jsonify({"ok": True, "status": "pending", "msg": "Generating image…"})
    elif status == "done":
        # Clean up task after delivering result
        with _bg_tasks_lock:
            _bg_tasks.pop(task_id, None)
        return jsonify({"ok": True, "status": "done", **task.get("result", {})})
    else:
        with _bg_tasks_lock:
            _bg_tasks.pop(task_id, None)
        result = task.get("result", {})
        code = 400 if result.get("code") else 500
        return jsonify({"ok": False, "status": "error", **result}), code


@app.route("/assets/room-reference", methods=["GET"])
def assets_room_reference():
    """Layout blueprint image for New Home / Custom Style generation."""
    if not os.path.exists(ROOM_REFERENCE_IMAGE):
        return jsonify({"ok": False, "msg": "room reference not found"}), 404
    ref_dir = os.path.dirname(ROOM_REFERENCE_IMAGE)
    ref_name = os.path.basename(ROOM_REFERENCE_IMAGE)
    return send_from_directory(ref_dir, ref_name)


@app.route("/assets/restore-reference-background", methods=["POST"])
def assets_restore_reference_background():
    """Restore office_bg_small.webp from fixed reference image."""
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        target = FRONTEND_PATH / "office_bg_small.webp"
        if not target.exists():
            return jsonify({"ok": False, "msg": "office_bg_small.webp not found"}), 404
        if not os.path.exists(ROOM_REFERENCE_IMAGE):
            return jsonify({"ok": False, "msg": "Reference room image not found"}), 404

        result = _activate_background_from_path(ROOM_REFERENCE_IMAGE, archive_current=True, from_reference=True)
        return jsonify({
            "ok": True,
            "path": "office_bg_small.webp",
            "size": result["size"],
            "archived": result.get("archived"),
            "msg": "Original background restored",
        })
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/restore-last-generated-background", methods=["POST"])
def assets_restore_last_generated_background():
    """Restore office_bg_small.webp from latest bg-history snapshot."""
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        target = FRONTEND_PATH / "office_bg_small.webp"
        if not target.exists():
            return jsonify({"ok": False, "msg": "office_bg_small.webp not found"}), 404

        if not os.path.isdir(BG_HISTORY_DIR):
            return jsonify({"ok": False, "msg": "No background history yet"}), 404

        files = [
            os.path.join(BG_HISTORY_DIR, x)
            for x in os.listdir(BG_HISTORY_DIR)
            if _safe_history_filename(x)
        ]
        if not files:
            return jsonify({"ok": False, "msg": "No background history yet"}), 404

        latest = max(files, key=lambda p: os.path.getmtime(p))
        result = _activate_background_from_path(latest, archive_current=True, from_reference=False)

        return jsonify({
            "ok": True,
            "path": "office_bg_small.webp",
            "size": result["size"],
            "from": os.path.relpath(latest, ROOT_DIR),
            "archived": result.get("archived"),
            "msg": "Restored last generated background",
        })
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/room-backgrounds/list", methods=["GET"])
def assets_room_backgrounds_list():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        items, active_id = _list_room_background_items()
        return jsonify({"ok": True, "items": items, "active_id": active_id, "count": len(items)})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/room-backgrounds/thumb/<path:item_id>", methods=["GET"])
def assets_room_backgrounds_thumb(item_id):
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    if item_id != "__default__":
        return jsonify({"ok": False, "msg": "not found"}), 404
    if not os.path.exists(ROOM_REFERENCE_IMAGE):
        return jsonify({"ok": False, "msg": "Reference room image not found"}), 404
    return send_from_directory(os.path.dirname(ROOM_REFERENCE_IMAGE), os.path.basename(ROOM_REFERENCE_IMAGE))


@app.route("/assets/room-backgrounds/apply", methods=["POST"])
def assets_room_backgrounds_apply():
    """Switch active background from gallery (default, public presets, or bg-history)."""
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        item_id = (data.get("id") or "").strip()
        if not item_id:
            return jsonify({"ok": False, "msg": "missing id"}), 400

        target = FRONTEND_PATH / "office_bg_small.webp"
        if not target.exists():
            return jsonify({"ok": False, "msg": "office_bg_small.webp not found"}), 404

        _, active_id = _list_room_background_items()
        if item_id == active_id:
            return jsonify({"ok": True, "id": item_id, "msg": "Already active", "already_active": True})

        if item_id == "__default__":
            if not os.path.exists(ROOM_REFERENCE_IMAGE):
                return jsonify({"ok": False, "msg": "Reference room image not found"}), 404
            result = _activate_background_from_path(ROOM_REFERENCE_IMAGE, archive_current=True, from_reference=True)
            return jsonify({
                "ok": True,
                "id": item_id,
                "path": "office_bg_small.webp",
                "size": result["size"],
                "archived": result.get("archived"),
                "msg": "Factory default applied",
            })

        if item_id.startswith("public:"):
            fn = _safe_public_gallery_filename(item_id[7:])
            if not fn:
                return jsonify({"ok": False, "msg": "invalid public gallery id"}), 400
            src = os.path.join(ROOM_GALLERY_PUBLIC_DIR, fn)
            if not os.path.exists(src):
                return jsonify({"ok": False, "msg": "public room background not found"}), 404
            from_reference = os.path.splitext(fn)[1].lower() in {".png", ".jpg", ".jpeg"}
            result = _activate_background_from_path(src, archive_current=True, from_reference=from_reference)
            return jsonify({
                "ok": True,
                "id": item_id,
                "path": "office_bg_small.webp",
                "size": result["size"],
                "from": os.path.relpath(src, ROOT_DIR),
                "archived": result.get("archived"),
                "msg": "Public room background applied",
            })

        fn = _safe_history_filename(item_id)
        if not fn:
            return jsonify({"ok": False, "msg": "invalid background id"}), 400
        src = os.path.join(BG_HISTORY_DIR, fn)
        if not os.path.exists(src):
            return jsonify({"ok": False, "msg": "background not found"}), 404

        result = _activate_background_from_path(src, archive_current=True, from_reference=False)
        return jsonify({
            "ok": True,
            "id": fn,
            "path": "office_bg_small.webp",
            "size": result["size"],
            "from": os.path.relpath(src, ROOT_DIR),
            "archived": result.get("archived"),
            "msg": "Room background applied",
        })
    except RuntimeError as e:
        return jsonify({"ok": False, "msg": str(e)}), 500
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/room-gallery/file/<path:filename>", methods=["GET"])
def assets_room_gallery_public_file(filename):
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    fn = _safe_public_gallery_filename(filename)
    if not fn:
        return jsonify({"ok": False, "msg": "not found"}), 404
    return send_from_directory(ROOM_GALLERY_PUBLIC_DIR, fn)


@app.route("/assets/bg-history/file/<path:filename>", methods=["GET"])
def assets_bg_history_file(filename):
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    fn = _safe_history_filename(filename)
    if not fn:
        return jsonify({"ok": False, "msg": "not found"}), 404
    return send_from_directory(BG_HISTORY_DIR, fn)


@app.route("/assets/home-favorites/list", methods=["GET"])
def assets_home_favorites_list():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = _load_home_favorites_index()
        items = data.get("items") or []
        out = []
        for it in items:
            rel = (it.get("path") or "").strip()
            if not rel:
                continue
            abs_path = os.path.join(ROOT_DIR, rel)
            if not os.path.exists(abs_path):
                continue
            fn = os.path.basename(rel)
            thumb = _home_fav_thumb_url(rel)
            out.append({
                "id": it.get("id"),
                "path": rel,
                "url": thumb,
                "thumb_url": thumb,
                "label": _history_label_from_filename(fn) if _safe_history_filename(fn) else fn,
                "created_at": it.get("created_at") or "",
            })
        out.sort(key=lambda x: x.get("created_at") or "", reverse=True)
        return jsonify({"ok": True, "items": out})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/home-favorites/save-current", methods=["POST"])
def assets_home_favorites_save_current():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        rel = _resolve_bg_history_rel_for_active_room()
        if not rel:
            return jsonify({
                "ok": False,
                "msg": "current room is not in gallery (e.g. factory default) — generate or switch rooms first",
            }), 400

        fn = os.path.basename(rel)
        item_id = fn.replace(".webp", "")

        idx = _load_home_favorites_index()
        items = idx.get("items") or []
        hit = next((x for x in items if (x.get("path") or "") == rel), None)
        if hit:
            return jsonify({
                "ok": True,
                "id": hit.get("id") or item_id,
                "path": rel,
                "msg": "Already in favorites",
            })

        items.insert(0, {
            "id": item_id,
            "path": rel,
            "created_at": datetime.now().isoformat(timespec="seconds"),
        })

        # ponytail: trim index only — bg-history files stay (shared with room gallery)
        if len(items) > HOME_FAVORITES_MAX:
            items = items[:HOME_FAVORITES_MAX]

        idx["items"] = items
        _save_home_favorites_index(idx)
        return jsonify({"ok": True, "id": item_id, "path": rel, "msg": "Current map saved to favorites"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/home-favorites/delete", methods=["POST"])
def assets_home_favorites_delete():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        item_id = (data.get("id") or "").strip()
        if not item_id:
            return jsonify({"ok": False, "msg": "missing id"}), 400

        idx = _load_home_favorites_index()
        items = idx.get("items") or []
        hit = next((x for x in items if (x.get("id") or "") == item_id), None)
        if not hit:
            return jsonify({"ok": False, "msg": "favorite not found"}), 404

        idx["items"] = [x for x in items if (x.get("id") or "") != item_id]
        _save_home_favorites_index(idx)
        return jsonify({"ok": True, "id": item_id, "msg": "Favorite removed (room file kept in gallery)"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/home-favorites/apply", methods=["POST"])
def assets_home_favorites_apply():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        item_id = (data.get("id") or "").strip()
        if not item_id:
            return jsonify({"ok": False, "msg": "missing id"}), 400

        idx = _load_home_favorites_index()
        items = idx.get("items") or []
        hit = next((x for x in items if (x.get("id") or "") == item_id), None)
        if not hit:
            return jsonify({"ok": False, "msg": "favorite not found"}), 404

        src = os.path.join(ROOT_DIR, hit.get("path") or "")
        if not os.path.exists(src):
            return jsonify({"ok": False, "msg": "favorite file not found"}), 404

        target = FRONTEND_PATH / "office_bg_small.webp"
        if not target.exists():
            return jsonify({"ok": False, "msg": "office_bg_small.webp not found"}), 404

        result = _activate_background_from_path(src, archive_current=True, from_reference=False)
        return jsonify({
            "ok": True,
            "path": "office_bg_small.webp",
            "size": result["size"],
            "from": hit.get("path"),
            "archived": result.get("archived"),
            "msg": "Favorite map applied",
        })
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/auth", methods=["POST"])
def assets_auth():
    try:
        data = request.get_json(silent=True) or {}
        pwd = (data.get("password") or "").strip()
        if pwd and pwd == ASSET_DRAWER_PASS_DEFAULT:
            session["asset_editor_authed"] = True
            return jsonify({"ok": True, "msg": "Authenticated"})
        return jsonify({"ok": False, "msg": "Wrong passcode"}), 401
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/auth/status", methods=["GET"])
def assets_auth_status():
    return jsonify({
        "ok": True,
        "authed": _is_asset_editor_authed(),
        "drawer_default_pass": ASSET_DRAWER_PASS_DEFAULT == "1234",
    })


@app.route("/assets/positions", methods=["GET"])
def assets_positions_get():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        return jsonify({"ok": True, "items": load_asset_positions()})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/positions", methods=["POST"])
def assets_positions_set():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        key = (data.get("key") or "").strip()
        x = data.get("x")
        y = data.get("y")
        scale = data.get("scale")
        if not key:
            return jsonify({"ok": False, "msg": "missing key"}), 400
        if x is None or y is None:
            return jsonify({"ok": False, "msg": "missing x/y"}), 400
        x = float(x)
        y = float(y)
        if scale is None:
            scale = 1.0
        scale = float(scale)

        all_pos = load_asset_positions()
        all_pos[key] = {"x": x, "y": y, "scale": scale, "updated_at": datetime.now().isoformat()}
        save_asset_positions(all_pos)
        return jsonify({"ok": True, "key": key, "x": x, "y": y, "scale": scale})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/defaults", methods=["GET"])
def assets_defaults_get():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        return jsonify({"ok": True, "items": load_asset_defaults()})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/defaults", methods=["POST"])
def assets_defaults_set():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        key = (data.get("key") or "").strip()
        x = data.get("x")
        y = data.get("y")
        scale = data.get("scale")
        if not key:
            return jsonify({"ok": False, "msg": "missing key"}), 400
        if x is None or y is None:
            return jsonify({"ok": False, "msg": "missing x/y"}), 400
        x = float(x)
        y = float(y)
        if scale is None:
            scale = 1.0
        scale = float(scale)

        all_defaults = load_asset_defaults()
        all_defaults[key] = {"x": x, "y": y, "scale": scale, "updated_at": datetime.now().isoformat()}
        save_asset_defaults(all_defaults)
        return jsonify({"ok": True, "key": key, "x": x, "y": y, "scale": scale})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/config/gemini/full", methods=["GET"])
def gemini_config_full():
    """Return full API key for in-browser generation (drawer auth required)."""
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        cfg = load_runtime_config()
        key = (cfg.get("gemini_api_key") or "").strip()
        if not key:
            return jsonify({"ok": False, "code": "MISSING_API_KEY", "msg": "Missing GEMINI_API_KEY"}), 400
        return jsonify({
            "ok": True,
            "api_key": key,
            "gemini_model": _normalize_user_model(cfg.get("gemini_model") or "nanobanana-pro"),
        })
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/config/gemini", methods=["GET"])
def gemini_config_get():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        cfg = load_runtime_config()
        key = (cfg.get("gemini_api_key") or "").strip()
        masked = ("*" * max(0, len(key) - 4)) + key[-4:] if key else ""
        return jsonify({
            "ok": True,
            "has_api_key": bool(key),
            "api_key_masked": masked,
            "gemini_model": _normalize_user_model(cfg.get("gemini_model") or "nanobanana-pro"),
        })
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/config/gemini", methods=["POST"])
def gemini_config_set():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        api_key = (data.get("api_key") or "").strip()
        model = _normalize_user_model((data.get("model") or "").strip() or "nanobanana-pro")
        payload = {"gemini_model": model}
        if api_key:
            payload["gemini_api_key"] = api_key
        save_runtime_config(payload)
        return jsonify({"ok": True, "msg": "Gemini config saved"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/restore-default", methods=["POST"])
def assets_restore_default():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        rel_path = (data.get("path") or "").strip().lstrip("/")
        if not rel_path:
            return jsonify({"ok": False, "msg": "missing path"}), 400

        target = (FRONTEND_PATH / rel_path).resolve()
        try:
            target.relative_to(FRONTEND_PATH.resolve())
        except Exception:
            return jsonify({"ok": False, "msg": "invalid path"}), 400

        if not target.exists():
            return jsonify({"ok": False, "msg": "target file not found"}), 404

        root, ext = os.path.splitext(str(target))
        default_path = root + ext + ".default"
        if not os.path.exists(default_path):
            return jsonify({"ok": False, "msg": "default asset snapshot not found"}), 404

        # 回滚前保留上一版
        bak = str(target) + ".bak"
        if os.path.exists(str(target)):
            shutil.copy2(str(target), bak)

        shutil.copy2(default_path, str(target))
        st = os.stat(str(target))
        return jsonify({"ok": True, "path": rel_path, "size": st.st_size, "msg": "Reset to default asset"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/restore-prev", methods=["POST"])
def assets_restore_prev():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        data = request.get_json(silent=True) or {}
        rel_path = (data.get("path") or "").strip().lstrip("/")
        if not rel_path:
            return jsonify({"ok": False, "msg": "missing path"}), 400

        target = (FRONTEND_PATH / rel_path).resolve()
        try:
            target.relative_to(FRONTEND_PATH.resolve())
        except Exception:
            return jsonify({"ok": False, "msg": "invalid path"}), 400

        bak = str(target) + ".bak"
        if not os.path.exists(bak):
            return jsonify({"ok": False, "msg": "previous version backup not found"}), 404

        shutil.copy2(str(target), bak + ".tmp") if os.path.exists(str(target)) else None
        shutil.copy2(bak, str(target))
        st = os.stat(str(target))
        return jsonify({"ok": True, "path": rel_path, "size": st.st_size, "msg": "Restored previous version"})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


@app.route("/assets/upload", methods=["POST"])
def assets_upload():
    guard = _require_asset_editor_auth()
    if guard:
        return guard
    try:
        rel_path = (request.form.get("path") or "").strip().lstrip("/")
        backup = (request.form.get("backup") or "1").strip() != "0"
        f = request.files.get("file")

        if not rel_path or f is None:
            return jsonify({"ok": False, "msg": "missing path or file"}), 400

        target = (FRONTEND_PATH / rel_path).resolve()
        try:
            target.relative_to(FRONTEND_PATH.resolve())
        except Exception:
            return jsonify({"ok": False, "msg": "invalid path"}), 400

        if target.suffix.lower() not in ASSET_ALLOWED_EXTS:
            return jsonify({"ok": False, "msg": "only image/asset uploads allowed"}), 400

        if not target.exists():
            return jsonify({"ok": False, "msg": "target not found — pick a path from /assets/list first"}), 404

        target.parent.mkdir(parents=True, exist_ok=True)

        # 首次上传前固化默认资产快照，供“重置为默认资产”使用
        default_snap = Path(str(target) + ".default")
        if not default_snap.exists():
            try:
                shutil.copy2(target, default_snap)
            except Exception:
                pass

        if backup:
            bak = target.with_suffix(target.suffix + ".bak")
            shutil.copy2(target, bak)

        auto_sheet = (request.form.get("auto_spritesheet") or "0").strip() == "1"
        ext_name = (f.filename or "").lower()

        if auto_sheet and target.suffix.lower() in {".webp", ".png"}:
            with tempfile.NamedTemporaryFile(suffix=os.path.splitext(ext_name)[1] or ".gif", delete=False) as tf:
                src_path = tf.name
                f.save(src_path)
            try:
                in_w, in_h = _probe_animated_frame_size(src_path)
                frame_w = int(request.form.get("frame_w") or (in_w or 64))
                frame_h = int(request.form.get("frame_h") or (in_h or 64))

                # 如果是静态图上传到精灵表目标，按网格切片而不是整图覆盖
                if not (ext_name.endswith(".gif") or ext_name.endswith(".webp")) and Image is not None:
                    try:
                        with Image.open(src_path) as sim:
                            sim = sim.convert("RGBA")
                            sw, sh = sim.size
                            if frame_w <= 0 or frame_h <= 0:
                                frame_w, frame_h = sw, sh
                            cols = max(1, sw // frame_w)
                            rows = max(1, sh // frame_h)
                            sheet_w = cols * frame_w
                            sheet_h = rows * frame_h
                            if sheet_w <= 0 or sheet_h <= 0:
                                raise RuntimeError("Static image size does not match frame grid")

                            cropped = sim.crop((0, 0, sheet_w, sheet_h))
                            # 目标是 webp 仍按无损保存，避免像素损失
                            if target.suffix.lower() == ".webp":
                                cropped.save(str(target), "WEBP", lossless=True, quality=100, method=6)
                            else:
                                cropped.save(str(target), "PNG")

                            st = target.stat()
                            return jsonify({
                                "ok": True,
                                "path": rel_path,
                                "size": st.st_size,
                                "backup": backup,
                                "converted": {
                                    "from": ext_name.split(".")[-1] if "." in ext_name else "image",
                                    "to": "webp_spritesheet" if target.suffix.lower() == ".webp" else "png_spritesheet",
                                    "frame_w": frame_w,
                                    "frame_h": frame_h,
                                    "columns": cols,
                                    "rows": rows,
                                    "frames": cols * rows,
                                    "preserve_original": False,
                                    "pixel_art": True,
                                }
                            })
                    finally:
                        pass

                # 默认：优先保留输入帧尺寸；若前端传了强制值则按前端。
                preserve_original_val = request.form.get("preserve_original")
                if preserve_original_val is None:
                    preserve_original = True
                else:
                    preserve_original = preserve_original_val.strip() == "1"

                pixel_art = (request.form.get("pixel_art") or "1").strip() == "1"
                req_cols = int(request.form.get("cols") or 0)
                req_rows = int(request.form.get("rows") or 0)
                sheet_path, cols, rows, frames, out_fw, out_fh = _animated_to_spritesheet(
                    src_path,
                    frame_w,
                    frame_h,
                    out_ext=target.suffix.lower(),
                    preserve_original=preserve_original,
                    pixel_art=pixel_art,
                    cols=(req_cols if req_cols > 0 else None),
                    rows=(req_rows if req_rows > 0 else None),
                )
                shutil.move(sheet_path, str(target))
                st = target.stat()
                from_type = "gif" if ext_name.endswith(".gif") else "webp"
                to_type = "webp_spritesheet" if target.suffix.lower() == ".webp" else "png_spritesheet"
                return jsonify({
                    "ok": True,
                    "path": rel_path,
                    "size": st.st_size,
                    "backup": backup,
                    "converted": {
                        "from": from_type,
                        "to": to_type,
                        "frame_w": out_fw,
                        "frame_h": out_fh,
                        "columns": cols,
                        "rows": rows,
                        "frames": frames,
                        "preserve_original": preserve_original,
                        "pixel_art": pixel_art,
                    }
                })
            finally:
                try:
                    os.remove(src_path)
                except Exception:
                    pass

        f.save(str(target))
        st = target.stat()
        return jsonify({"ok": True, "path": rel_path, "size": st.st_size, "backup": backup})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e)}), 500


if __name__ == "__main__":
    raw_port = os.environ.get("STAR_BACKEND_PORT", "19000")
    try:
        backend_port = int(raw_port)
    except ValueError:
        backend_port = 19000
    if backend_port <= 0:
        backend_port = 19000

    print("=" * 50)
    print("Star Office UI - Backend State Service")
    print("=" * 50)
    print(f"State file: {STATE_FILE}")
    print(f"Listening on: http://0.0.0.0:{backend_port}")
    if backend_port != 19000:
        print(f"(Port override: set STAR_BACKEND_PORT to change; current: {raw_port})")
    else:
        print("(Set STAR_BACKEND_PORT to use a different port, e.g. 3009)")
    mode = "production" if is_production_mode() else "development"
    print(f"Mode: {mode}")
    if is_production_mode():
        print("Security hardening: ENABLED (strict checks)")
    else:
        weak_flags = []
        if not is_strong_secret(str(app.secret_key)):
            weak_flags.append("weak FLASK_SECRET_KEY/STAR_OFFICE_SECRET")
        if not is_strong_drawer_pass(ASSET_DRAWER_PASS_DEFAULT):
            weak_flags.append("weak ASSET_DRAWER_PASS")
        if weak_flags:
            print("Security hardening: WARNING (dev mode) -> " + ", ".join(weak_flags))
        else:
            print("Security hardening: OK")
    print("=" * 50)

    app.run(host="0.0.0.0", port=backend_port, debug=False)

