"""Shared room-background generation prompt (New Home / Custom Style)."""

from __future__ import annotations

# Keep frontend _buildRoomGenPrompt() in index.html aligned with this module.

ROOM_GEN_LAYOUT_RULES = (
    "Use the provided reference image as the STRICT layout blueprint for a top-down pixel office "
    "scene (1280×720). Copy the same three-room geometry, camera angle, floor checkerboard, "
    "vertical room dividers/pillars, and centered empty rug in each room. "
    "Change ONLY visual style — colors, materials, lighting, mood — per: {style_hint}. "
    "No text or watermarks. Retro 8-bit RPG pixel art. "
    "FLOOR / RUG (critical — separate sprites overlay these rugs): keep every center rug "
    "completely empty. NEVER paint desks, PCs, monitors, keyboards, office chairs, sofas, beds, "
    "coffee tables, meeting tables, dining tables, or floor plants on or overlapping any rug. "
    "Game sprite anchors: LEFT rug — PC desk at (218,417); CENTER — sofa at (798,272) and "
    "meeting desk with team monitors at (659,384); RIGHT lower rug — character idle zone. "
    "WALL / BACK DECOR (like reference): LEFT room (x≈0–420) — back wall may have bookshelf, "
    "floor lamp, small cabinet along the upper-right portion only; framed posters on the back "
    "brick wall (hung on wall, not overlapping floor props). CENTER room (x≈420–860) — back-wall "
    "shelves, lamps, small wall posters OK. RIGHT room (x≈860–1280) — server racks, warning "
    "lights, filing cabinets on upper back wall OK. "
    "FORBIDDEN: no new décor on vertical partition walls/pillars between rooms; nothing on the "
    "left-facing sides of dividers; in the left room add back-wall items only toward the right "
    "side of that room — never blocking the center rug."
)


def build_room_gen_prompt(style_hint: str) -> str:
    hint = (style_hint or "").strip() or "cozy pixel office"
    return ROOM_GEN_LAYOUT_RULES.format(style_hint=hint)
