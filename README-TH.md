<p align="center">
  <img src="assets/loom-logo.svg" alt="Loom logo" width="140">
</p>

<h1 align="center">Loom</h1>

<p align="center"><strong>ทีม AI Agent</strong> — loop วางแผน → สร้าง → ตรวจ</p>

<p align="center">
  <img src="https://img.shields.io/badge/works%20with-9%20agents-6366f1?style=flat-square" alt="9 agents">
  <img src="https://img.shields.io/badge/platform-Claude%20Code%20%7C%20Cursor%20%7C%20Hermes-0ea5e9?style=flat-square" alt="platform">
</p>

> **[English](README.md)** · **ไทย** · **[Full docs (EN)](README.full.md)** · **[เอกสารเต็ม (TH)](README-TH.full.md)**

ทีม agent 9 ตัว ทำงานเป็น loop เดียว repo นี้คือ **พิมพ์เขียว (Base)** — โค้ดแอปจริงอยู่ที่อื่น (`loop.config.json` → `services[].path`)

## เริ่มต้นเร็ว

### 1. ติดตั้ง (ครั้งเดียว)

```zsh
git clone <repo-url> loom && cd loom
./loom wrap claude          # Claude Code — bootstrap อัตโนมัติครั้งแรก
# หรือ: zsh tools/deploy.sh   # ติดตั้งเต็ม + dashboard
```

ครั้งแรกจะเขียน `~/.loop-base` sync agents ไป **Claude Code · Cursor · Hermes** และต่อ hooks

**ทุกครั้งที่ใช้งาน** (จากโฟลเดอร์ไหนก็ได้):

```zsh
loom wrap claude
```

แสดง banner LOOM + path blueprint แล้วเปิด **Claude Code โดย cwd = blueprint** สตาร์ท dashboard ก่อน แล้ว **`--agent loom-start`** + ข้อความแรก **`Use loom-start`** ข้ามด้วย `LOOM_WRAP_NO_START=1`

<p align="center">
  <img src="assets/loom-wrap-claude-demo.gif" alt="loom wrap claude — banner ในเทอร์มินัล เปิด Claude Code พร้อม Use loom-start อัตโนมัติ loom where แล้วเปิด dashboard ที่ localhost:19000" width="820">
</p>

<p align="center">
  <em><code>loom wrap claude</code> → Claude เรียก <code>loom-start</code> ให้ · <code>loom where</code> ดูสถานะ blueprint · dashboard ที่ <code>http://localhost:19000</code></em>
</p>

### 2. เริ่มโปรเจกต์

ในแชต (ทุกแพลตฟอร์ม):

```
Use loom-start
```

ขั้นตอน: dashboard → base folder → control folder → **เลือก platform + model** → ส่งต่อ orch

ค่า default: Cursor `composer-2.5` · Claude `sonnet` · Hermes `inherit`

### 3. รัน loop

```
Use loom-orch at L1: <อธิบาย feature หรือ bug>
```

`L1` = วางแผนอย่างเดียว · `L2` = maker เขียนโค้ด คุณ merge · `L3` = อัตโนมัติ (มี safety limit)

### สรุปแพลตฟอร์ม

| แพลตฟอร์ม | เริ่ม | รัน loop |
| --------- | ----- | -------- |
| **Claude Code** | `loom wrap claude` แล้ว `Use loom-start` | `Use loom-orch at L1: …` |
| **Cursor** | เปิด repo นี้ → `Use loom-start` | `Use loom-orch at L1: …` |
| **Hermes** | `/loom-start` | `/loom-orch` |

เลือก **อย่างใดอย่างหนึ่ง** — ไม่จำเป็นต้องมีครบทั้งสาม

## Dashboard

`loom wrap claude` สตาร์ท board กลางใน background เปิดซ้ำได้ตลอด:

```zsh
loom where          # path blueprint + โปรเจกต์ active
loom dash serve     # เปิด http://localhost:19000
```

<p align="center">
  <picture>
    <source srcset="assets/loom-dashboard-show.gif" type="image/gif">
    <img src="assets/loom-dashboard-show.png" alt="Loom status dashboard — pixel office พร้อม activity feed" width="820">
  </picture>
</p>

<p align="center">
  <em>Live board — pixel office + Loop Activity. Office UI จาก <a href="https://github.com/ringhyacinth/Star-Office-UI">Star-Office-UI</a>.</em>
</p>

## คำสั่งประจำวัน

```zsh
loom where              # blueprint + โปรเจกต์ active
loom dash serve         # dashboard → http://localhost:19000
zsh tools/refresh.sh    # หลัง git pull — sync agents
```

## สถาปัตยกรรมสามชั้น (Three-layer architecture)

Loom แยก **ทีม** (ใช้ร่วมกัน) · **config งาน** (ต่อโปรเจกต์) · **โค้ดจริง** (repo ของคุณ):

```
Base (repo นี้)           Control folder              โค้ดจริง
─────────────────         ─────────────────           ─────────────────
agents · tools ·          loop.config.json            services[].path
dashboard                 STATE.md                    → FE/BE อยู่ที่ไหนก็ได้
(ห้าม copy)               (1 งาน = 1 โฟลเดอร์)         บนดิสก์
```

| ชั้น | ที่อยู่ | เก็บอะไร | เปรียบเทียบ |
| ---- | ------- | -------- | ----------- |
| **Base** | repo `loom` นี้ | `.claude/agents/`, `tools/`, `agent-dashboard/` | **ทีม + กล่องเครื่องมือ** — ใช้ร่วมทุกงาน; อ้างผ่าน `~/.loop-base` |
| **Control** | `~/Documents/coding/agent-build/<job>/` | `loop.config.json` + `STATE.md` เท่านั้น | **โต๊ะงาน** — ชี้ service ไหน, autonomy, ความจำ loop |
| **Code** | path ใน `services[]` | repo frontend / backend | ที่ agent **แก้โค้ดจริง** — relative, repo แยก, หรือ absolute path |

**base folder vs control folder**

| | **base folder** | **control folder** |
| --- | --- | --- |
| คำถาม | งานทั้งหมดอยู่ที่ไหน? | เปิดงานไหน? |
| ตัวอย่าง | `~/Documents/coding/agent-build` | `~/Documents/coding/agent-build/shop` |
| เก็บ | หลายโฟลเดอร์งาน (ไม่มี config) | `loop.config.json` + `STATE.md` ชุดเดียว |

control folder เดียวลิสต์ **หลาย service** ได้ (เช่น `web` + `api`) ใน config เดียว — `path` เป็น relative (ใต้ control) หรือ absolute (`~/…`) สำหรับ legacy code ที่อื่น

**กฎสำคัญ**

- ห้ามเขียน `loop.config.json` ใน Base — `loom-start` สร้าง control folder ใต้ base folder
- agents sync ไป `~/.claude/agents` / `~/.cursor/agents` / `~/.hermes/skills` — ไม่ copy ต่อโปรเจกต์
- `.active-project` ใน Base ชี้ control folder ที่กำลังทำงาน

→ อ่านละเอียด: [เอกสารเต็ม — สถาปัตยกรรม 3 ชั้น](README-TH.full.md#สถาปัตยกรรม-3-ชั้น)

## ทีม agent (ย่อ)

| Agent | หน้าที่ |
| ----- | ------- |
| `loom-start` | เลือก/สร้างโปรเจกต์ — **เริ่มที่นี่** |
| `loom-orch` | Orchestrator — รัน loop |
| `loom-pm` | ความต้องการ + AC |
| `loom-ux-ui` | UX/UI spec |
| `loom-fe` / `loom-motion` | Frontend / 3D & motion |
| `loom-be` / `loom-full-stack` | Backend / data & security |
| `loom-qa` | เทส + PASS/FAIL |

## หลัง `git pull`

```zsh
zsh tools/refresh.sh
Use loom-start                    # โปรเจกต์เก่า → model gate ครั้งเดียว
zsh "$(cat ~/.loop-base)/tools/apply-agent-model.sh"   # จาก control folder
```

Reload Cursor: **Cmd+Shift+P** → **Developer: Reload Window**

## เครดิต & ขอบคุณ

### Dashboard — [Star-Office-UI](https://github.com/ringhyacinth/Star-Office-UI)

<p align="center">
  <a href="https://github.com/ringhyacinth/Star-Office-UI">
    <img src="assets/star-office-ui-credit.png" alt="Star Office UI — pixel office dashboard by Ring Hyacinth and Simon Lee" width="480">
  </a>
</p>

<p align="center">
  <strong><a href="https://github.com/ringhyacinth/Star-Office-UI">Star-Office-UI</a></strong>
  โดย <a href="https://github.com/ringhyacinth">Ring Hyacinth</a>
  &amp; <a href="https://x.com/simonxxoo">Simon Lee</a>
  — โค้ด MIT; art assets <strong>ใช้เรียนรู้แบบไม่เชิงพาณิชย์เท่านั้น</strong>
  Loom นำมาใช้และปรับแต่งที่ <code>agent-dashboard/star-office/</code>
  (Loop Activity panel, agent bridge, activity feed)
</p>

### Skills & ไลบรารีภายนอก

| เครดิต | แหล่งที่มา |
| ------ | ---------- |
| **ponytail** (review / audit) | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |
| **loom-me** (PM workflow grilling) | [mattpocock/skills — loop-me](https://github.com/mattpocock/skills/tree/main/skills/in-progress/loop-me) |
| **ui-ux-pro-max** | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) |
| **hexagonal-architecture** | [affaan-m/ECC](https://github.com/affaan-m/ECC/blob/main/skills/hexagonal-architecture/SKILL.md) |
| **qa-browser** | [browser-use/browser-use](https://github.com/browser-use/browser-use) |
| **docker-containerization** | [ailabs-393/ai-labs-claude-skills](https://skills.sh/ailabs-393/ai-labs-claude-skills/docker-containerization) |
| **pm-skills** | [phuryn/loom-pm-skills](https://github.com/phuryn/loom-pm-skills) |

แนวทาง loop → [LOOP.md](LOOP.md) · [Loop Engineering Guide 2026](https://tosea.ai/blog/loop-engineering-ai-agents-complete-guide-2026)

รายการ skill เต็ม → [เอกสารเต็ม — เครดิต](README-TH.full.md#เครดิตและขอบคุณ)

---

**อ่านต่อ?** สถาปัตยกรรม, `loop.config.json`, legacy code, skills, อัปเกรด → **[Full README (EN)](README.full.md)** · **[เอกสารเต็ม (TH)](README-TH.full.md)**
