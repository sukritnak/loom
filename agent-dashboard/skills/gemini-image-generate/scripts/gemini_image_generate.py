#!/usr/bin/env python3
"""Generate images via Gemini API. Used by star-office backend (New Home / Custom Style)."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

from google import genai
from google.genai import types
from PIL import Image


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate an image with Gemini")
    p.add_argument("--prompt", required=True)
    p.add_argument("--model", default=os.getenv("GEMINI_MODEL", "gemini-2.5-flash-image"))
    p.add_argument("--out-dir", required=True)
    p.add_argument("--reference-image", default="")
    p.add_argument("--aspect-ratio", default="")
    p.add_argument("--cleanup", action="store_true", help="unused; kept for backend CLI compat")
    return p.parse_args()


def _api_key() -> str:
    key = (os.getenv("GEMINI_API_KEY") or "").strip()
    if not key:
        print("GEMINI_API_KEY is not set", file=sys.stderr)
        sys.exit(1)
    return key


def _client():
    referer = (os.getenv("GEMINI_HTTP_REFERER") or "").strip()
    if referer and not referer.endswith("/"):
        referer += "/"
    kwargs = {"api_key": _api_key()}
    if referer:
        kwargs["http_options"] = types.HttpOptions(headers={"Referer": referer})
    return genai.Client(**kwargs)


def _image_config(aspect_ratio: str) -> types.ImageConfig | None:
    if not aspect_ratio:
        return None
    return types.ImageConfig(aspect_ratio=aspect_ratio)


def _save_image(img: Image.Image, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "generated.png"
    img.save(out_path, "PNG")
    return out_path


def main() -> int:
    args = _parse_args()
    out_dir = Path(args.out_dir)
    client = _client()

    contents: list = []
    ref = (args.reference_image or "").strip()
    if ref:
        if not os.path.exists(ref):
            print(f"Reference image not found: {ref}", file=sys.stderr)
            return 1
        contents.append(Image.open(ref))

    contents.append(args.prompt)

    cfg_kwargs: dict = {"response_modalities": ["IMAGE"]}
    img_cfg = _image_config((args.aspect_ratio or "").strip())
    if img_cfg is not None:
        cfg_kwargs["image_config"] = img_cfg

    try:
        response = client.models.generate_content(
            model=args.model,
            contents=contents,
            config=types.GenerateContentConfig(**cfg_kwargs),
        )
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1

    saved: Path | None = None
    for part in response.parts or []:
        if part.inline_data is not None:
            sdk_img = part.as_image()
            pil = getattr(sdk_img, "_pil_image", None) or sdk_img
            if hasattr(pil, "save"):
                saved = _save_image(pil, out_dir)
                break

    if saved is None:
        print("Model returned no image", file=sys.stderr)
        return 1

    print(json.dumps({"files": [str(saved)]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
