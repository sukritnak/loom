<p align="center">
  <img src="assets/loom-logo.svg" alt="Loom logo" width="160">
</p>

<h1 align="center">Loom</h1>

<p align="center"><strong>AI Agent Software Team</strong> — พิมพ์เขียวกลางสำหรับ loop วางแผน → สร้าง → ตรวจ</p>

<p align="center"><em>เก้าตัวแทน หนึ่งเส้นด้าย ทอ loop จนส่งงานได้</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/works%20with-9%20agents-6366f1?style=flat-square" alt="works with 9 agents">
  <img src="https://img.shields.io/badge/platform-Claude%20Code%20%7C%20Cursor%20%7C%20Hermes-0ea5e9?style=flat-square" alt="platform">
  <img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square" alt="MIT license">
</p>

> **ภาษา:** [English](README.md) · **ไทย** (เอกสารนี้)
>
> **Workspace:** clone หรือเปิด repo นี้ชื่อ **`loom`** (พิมพ์เขียว — ไม่ใช่โค้ดแอป)

ทีม **AI agent 9 ตัว** ทำงานเป็น **loop** (วางแผน → สร้าง → ตรวจ → วน) ใช้ได้ทั้ง **Claude Code · Cursor · Hermes**

> repo นี้คือ **พิมพ์เขียว (Base)** — ไม่ใช่ที่เก็บโค้ดงานจริง
> โค้ดจริงอยู่ที่ `services[].path` ใน `loop.config.json` (relative หรือ absolute)
> โฟลเดอร์ control (config + STATE) ถูกสร้างที่ `<base-dir>/<name>` ดีฟอลต์ `~/Documents/coding/agent-build`

**ทำไมชื่อ Loom?** แนวเดียวกับ Hermes (ส่งงาน) หรือ Ponytail (โค้ดน้อยที่สุด) — **Loom** คือที่ *ทอ* loop ซอฟต์แวร์: วางแผน → สร้าง → ตรวจ → วนใหม่ ด้วยทีม agent บนเส้นด้ายเดียว ชื่อสั้นของพิมพ์เขียว; แอปจริงยังอยู่ที่ control folder และ service path

---

## สถาปัตยกรรม 3 ชั้น

| อะไร | **Base** (repo นี้) | **Control folder** (`<base-dir>/<name>`) |
| ---- | -------------------- | ---------------------------------------- |
| **บทบาท** | พิมพ์เขียว — ใช้ร่วมทุกงาน | หนึ่งงาน — มีแค่ config + memory |
| **ทีม agent** | `.claude/agents/` | — (ติดตั้งระดับเครื่องผ่าน `deploy.sh`) |
| **Hermes skills** | `hermes-skills/` | — |
| **tools ร่วม** | `tools/` | — (เรียก Base ผ่าน `~/.loop-base`) |
| **Dashboard** | `agent-dashboard/` | — |
| **config งาน** | — | `loop.config.json` — services, mode, autonomy |
| **ความจำ loop** | — | `STATE.md` — ต่อ session ได้ |
| **โค้ดแอป** | — | `services[].path` — อาจอยู่ที่อื่นบนดิสก์ |

| ชั้น | ตำแหน่ง | เนื้อหา |
| ----- | -------- | -------- |
| **Base** | repo นี้ | นิยาม agent, tools, dashboard, LOOP.md — **ไม่คัดลอกไปปลายทาง** |
| **control folder** | `<base-dir>/<name>` | `loop.config.json` + `STATE.md` เท่านั้น |
| **โค้ดจริง** | ตาม `services[].path` | frontend / backend ที่ agent แก้ (อาจเป็น repo แยก) |

**กฎสำคัญ**
- ห้ามสร้างโปรเจกต์หรือเขียน `loop.config.json` ใน Base / โฟลเดอร์ปัจจุบัน
- agent ติดตั้งระดับเครื่อง (`~/.claude/agents`, `~/.hermes/skills`) → ใช้ได้จากทุกโปรเจกต์
- tools + dashboard หา Base ผ่าน `~/.loop-base` (เขียนโดย `deploy.sh` หรือ `new-project.sh`)
- 1 งาน = 1 control folder = 1 session แยกได้
- `.active-project` ใน Base เก็บ path ของ control folder ที่ active (`loop-start` เขียนให้)

**กำหนด base folder เอง** ผ่าน `loop-start` หรือ env `BASE_DIR=/path`
ลำดับการ resolve: arg > `BASE_DIR` > ไฟล์ `.base-dir` ใน Base > ดีฟอลต์ `~/Documents/coding/agent-build`
ต้องเป็น absolute path และอยู่นอก Base

### โฟลเดอร์ base กับ control folder

| | **base folder** | **control folder** |
| - | --------------- | ------------------ |
| **คำถาม** | **งานทั้งหมด** อยู่ที่ไหน? | เปิด **งานไหน** ในนั้น? |
| **ตัวอย่าง path** | `~/Documents/coding/agent-build` | `~/Documents/coding/agent-build/shop` |
| **เนื้อหา** | "ชั้นวาง" หลายงาน (ไม่มี config) | `loop.config.json` + `STATE.md` ของงานนั้น |
| **จำนวน** | มักมี **หนึ่ง** ต่อเครื่อง | **หลาย** งาน — งานละโฟลเดอร์ |
| **services** | N/A | control เดียวมี **หลาย service** ใน config เดียวได้ |

```
Use loop-start / /loop-start

Step 1 — base folder (ชั้นวางงาน)
  ถาม path → สร้างด้วย mkdir -p ถ้ายังไม่มี
  ~/Documents/coding/agent-build/          ← ★ สร้าง base folder ที่นี่ (ถ้ายังไม่มี)

Step 2 — control folder (งานเดียว)
  2a เปิดของเดิม → ไม่สร้างโฟลเดอร์ใหม่ (เลือกจากรายการใต้ base)
  2b สร้างใหม่   → ★ สร้าง control folder + loop.config.json + STATE.md
    ├── shop/          ← control job A
    ├── portal/        ← control job B
    └── my-app/        ← control job C

Step 3 — lock เป้า (.active-project ใน Loom) — ไม่สร้างโฟลเดอร์
```

| ขั้น `loop-start` | สร้างอะไร? | ตัวอย่าง |
| ----------------- | ---------- | -------- |
| **Step 1** | **base folder** (ถ้ายังไม่มี) | `mkdir -p ~/Documents/coding/agent-build` |
| **Step 2a** เปิดของเดิม | ไม่สร้าง — เลือก control ที่มี config แล้ว | เลือก `shop/` จากรายการ |
| **Step 2b** สร้างใหม่ | **control folder** + `loop.config.json` + `STATE.md` | `mkdir -p …/agent-build/shop` แล้วเขียน config |
| **Step 3** | `.active-project` ใน Loom (Blueprint) เท่านั้น | ไม่สร้างโฟลเดอร์งาน |

> **Blueprint (Base = repo Loom นี้)** ไม่ได้สร้างโดย `loop-start` — clone repo แล้วรัน `deploy.sh` ครั้งเดียว

**base ส่งผลต่อ control อย่างไร**

| หัวข้อ | base มีผล? |
| ----- | ------------- |
| สร้าง control folder ใหม่ | ใช่ — เสมอ `<base>/<job-name>/` |
| แสดงรายการงานใน `loop-start` | ใช่ — สแกน `base/*/loop.config.json` |
| เนื้อหา `loop.config.json` | ไม่ — services / mode / path อยู่ใน control ไม่ผูกกับ base |
| path **relative** ของ service | ไม่ — resolve จาก **control folder** ไม่ใช่ base |
| path **absolute** ของ service | ไม่ — ชี้ไปที่ไหนบนดิสก์ก็ได้ |
| เปลี่ยน base ทีหลัง | งานเก่าไม่ย้าย — control อยู่ path เดิม |

> **control folder ≠ 1 service** — control เดียวลิสต์หลาย service (เช่น frontend + api) ใน `loop.config.json` เดียวได้

---

## การทำงาน (ภาพรวม)

### โครงสร้างระบบ

```mermaid
flowchart TB
  subgraph loom ["Loom — Blueprint (repo นี้)"]
    agents["นิยาม agent 9 ตัว"]
    tools["tools ร่วม"]
    dash["dashboard กลาง"]
  end

  subgraph job ["Control folder — หนึ่งงานหนึ่งโฟลเดอร์"]
    cfg["loop.config.json"]
    mem["STATE.md"]
  end

  subgraph services ["โค้ดจริง — services[].path"]
    fe["Frontend repo(s)"]
    be["Backend repo(s)"]
  end

  you(["คุณ"]) -->|loop-start| job
  job -->|loop-orch มอบหมาย| agents
  agents -->|แก้ไข| fe
  agents -->|แก้ไข| be
  agents -->|dash.sh / hooks| dash
  cfg -.->|ชี้ไป| fe
  cfg -.->|ชี้ไป| be
  tools --> job
```

### วง loop (หนึ่งรอบ)

```mermaid
flowchart TD
  A([งานใหม่]) --> B[loop-orch โหลด STATE + config]
  B --> C[PM: acceptance criteria]
  C --> D{มี UI?}
  D -->|ใช่| E[Designer: flow + states]
  D -->|ไม่| F
  E --> F[BE / FE build คู่ขนาน]
  F --> G[QA: test + browser AC]
  G -->|PASS| H([อัปเดต STATE.md · human gate ถ้า L1/L2])
  G -->|FAIL| I[PM triage → ส่ง feedback]
  I -->|รอบ ≤ 3| F
  I -->|ติด / ไม่คืบหน้า| J([Human gate])
```

### ข้อมูลไหลเข้า dashboard

ออฟฟิศพิกเซลมาจาก **[Star-Office-UI](https://github.com/ringhyacinth/Star-Office-UI)** (vendored ที่ `agent-dashboard/star-office/`) Loom เพิ่ม bridge และ activity feed ทับอีกชั้น

```mermaid
flowchart LR
  orch["loop-orch / makers"]
  cli["zsh tools/dash.sh"]
  hook["Claude Code hooks<br/>cc-dash-bridge.js"]
  json["status.json"]
  bridge["star-office-bridge.js"]
  ui["Star-Office UI<br/>:19000"]

  orch --> cli
  hook --> cli
  cli --> json
  json --> bridge
  bridge --> ui
```

---

### ตัวอย่าง: โค้ดอยู่ที่หนึ่ง control อยู่อีกที่

สมมติ repo เก่าอยู่ใต้ `~/Documents/coding/legacy/` (โค้ดไม่ย้าย):

```
~/Documents/coding/legacy/              ← โค้ดจริง (ไม่ใช่ base ไม่ใช่ control)
├── shop-frontend/
├── shop-core/
├── portal-client/
├── portal-core/
└── portal-data/
```

ตั้ง **base** = `~/Documents/coding/agent-build` สร้าง **control** ต่องาน:

```
~/Documents/coding/agent-build/
├── shop/                               ← control job A
│   ├── loop.config.json                ← 2 services ชี้กลับ legacy/
│   └── STATE.md
└── portal/                             ← control job B
    ├── loop.config.json                ← 3 services ชี้กลับ legacy/
    └── STATE.md
```

`loop.config.json` ของงาน `shop` (`mode: existing` ไม่ย้ายโค้ด):

```json
{
  "project": "shop",
  "mode": "existing",
  "autonomy": "L1",
  "services": [
    { "id": "frontend", "side": "fe", "path": "~/Documents/coding/legacy/shop-frontend", "stack": "" },
    { "id": "core",     "side": "be", "path": "~/Documents/coding/legacy/shop-core",     "stack": "" }
  ]
}
```

งาน `portal` เป็นอีก control — สาม service ชี้ไป `portal-*` ใต้ `legacy/`

**ทำไมไม่รวม base + control + โค้ดในโฟลเดอร์เดียว?**

| แนวทาง | ผลลัพธ์ |
| -------- | ------ |
| control = โฟลเดอร์เดียวกับโค้ด (`legacy/loop.config.json`) | **งานเดียวเท่านั้น** — เขียน config เอง + `cd` ไปที่นั่น |
| หลายงานในโฟลเดอร์เดียว | **ไม่รองรับ** — มีได้แค่ `loop.config.json` + `STATE.md` เดียว (config/ความจำชนกัน) |
| แยก control ใต้ base (แนะนำ) | session คู่ขนาน สลับ `shop` / `portal` ผ่าน `cd` หรือ `loop-start` |

---

## เริ่มต้นใช้งาน

### 1) ติดตั้งทีม (ครั้งเดียวต่อเครื่อง) — รันจาก Base

```zsh
zsh tools/deploy.sh
```

คำสั่งแรกทำครบ:

| ขั้น | ทำอะไร |
| ---- | ------------ |
| agents | คัดลอก subagent → `~/.claude/agents/` |
| Hermes | ติดตั้ง team skills → `~/.hermes/skills/` |
| **external skills** | ติดตั้งที่แนะนำ → `~/.agents/skills/` + Hermes symlinks |
| Base path | ลงทะเบียน `~/.loop-base` |
| dashboard | เปิด `http://localhost:19000` |

ข้าม external skills (ไม่มีเน็ต / ติดตั้งทีหลัง):

```zsh
DEPLOY_SKIP_EXTERNAL_SKILLS=1 zsh tools/deploy.sh
```

ติดตั้ง external skills ทีหลังหรือลองใหม่หลังข้าม:

```zsh
zsh tools/install-external-skills.sh && zsh tools/install-hermes-skills.sh
```

**External skills ที่ deploy ติดตั้ง**

| skill | ใช้โดย | วัตถุประสงค์ |
| ----- | ------- | ------- |
| `solid` | fe, be | SOLID, TDD, clean code |
| `ponytail` | fe, be | โค้ดน้อยที่สุดที่ใช้ได้ |
| `ponytail-review` | fe, be | รีวิว over-engineering / legacy orient |
| `ponytail-audit` | loop-orch | สแกนหนี้เทคนิคทั้ง service (เมื่อจำเป็น) |
| `postgres-best-practices` | be-sr | DB / Postgres |
| `docker-containerization` | ทุก agent | [ailabs-393/ai-labs-claude-skills](https://skills.sh/ailabs-393/ai-labs-claude-skills/docker-containerization) |
| `hexagonal-architecture` | be, be-sr | Ports & Adapters — [affaan-m/ECC](https://github.com/affaan-m/ECC) |
| `threejs-animation` | fe-anim | 3D / motion |
| `perf-lighthouse` | qa, fe | ตรวจประสิทธิภาพเว็บ |
| `qa-browser` | qa | ทดสอบ FE/UI บนเบราว์เซอร์จริง |

หลังแก้นิยาม agent ให้ sync ทุกแพลตฟอร์ม:

```zsh
zsh tools/sync-agents.sh    # source = .claude/agents/
```

### 2) เริ่มงาน — คำสั่งแชต (หลัก)

**งานใหม่หรือต่อโปรเจกต์เดิม** — คำสั่งเดียวกัน ไม่ต้อง `cd` เองถ้าอยู่ใน Base:

```
Use loop-start      ← Claude Code / Cursor
/loop-start         ← Hermes
```

`loop-start` / `/loop-start` พาไล่ทีละขั้น (ดู [base กับ control](#โฟลเดอร์-base-กับ-control-folder)):

| ขั้น | คำสั่ง | สร้างอะไร |
| ---- | ------ | --------- |
| **1** | `Use loop-start` / `/loop-start` → ถาม path | **base folder** — `mkdir -p` ถ้ายังไม่มี (ดีฟอลต์ `~/Documents/coding/agent-build`) |
| **2a** | เลือก **(1) open existing** | **ไม่สร้าง** — เลือก control folder ที่มี `loop.config.json` แล้ว |
| **2b** | เลือก **(2) create new** → ชื่องาน, mode, services | **control folder** ที่ `<base>/<job-name>/` + `loop.config.json` + `STATE.md` |
| **3** | lock เป้า | เขียน `.active-project` ใน Loom — ไม่สร้างโฟลเดอร์ |
| **4** | hand off | ส่งต่อ `loop-orch` |

รายละเอียดย่อ:
1. **Step 1** — base folder (ชั้นวาง) — สร้างโฟลเดอร์ชั้นวาง **ถ้ายังไม่มี**
2. **Step 2** — control folder — **2a** เปิดของเดิม (ไม่สร้าง) · **2b** สร้างใหม่ → `<base>/<job-name>/`
3. **(2b เท่านั้น)** mode (`new` / `existing`), autonomy (L1/L2/L3), services (id / side / path / stack)
4. เขียน/ยืนยัน `loop.config.json` + `STATE.md` ที่ control folder แล้วส่งต่อ `loop-orch`

> `loop-start` เลือกโปรเจกต์ที่ถูกก่อนเริ่มงานเสมอ
> `loop-orch` เช็ก `loop.config.json` ใน cwd ก่อน ถ้าไม่มีจะอ่าน `.active-project` (กันแก้ผิดโปรเจกต์)

รายละเอียดต่อ session เดิม → [ต่อ session เดิม](#ต่อ-session-เดิม--เปิดโปรเจกต์ที่ตั้งค่าไว้แล้ว)

จากนั้นมอบหมายงาน:

```
Use loop-orch at L1: <อธิบายฟีเจอร์หรือบั๊ก>
```

Hermes: `/loop-orch run at L1: <task>`

`loop-orch` จะถาม **「เปิด dashboard ดู agent ทำงานไหม? [Y/n]」** (ดีฟอลต์ Y) ก่อนส่งงานให้ agent ใด ๆ — ตอบ Y หรือ Enter แล้วเปิด browser ที่ `http://localhost:19000` อัตโนมัติ

### 3) ทางเลือกผ่าน terminal

```zsh
zsh tools/deploy.sh                  # ติดตั้งทีม (ครั้งเดียวต่อเครื่อง)
zsh tools/loop-start.sh              # wizard Steps 1–4 (base → control → lock → hand off)
zsh tools/new-project.sh my-app      # shortcut: Step 1 + 2b (--new)
zsh tools/dash.sh serve              # เปิดกระดานกลาง (Star-Office)
```

`new-project.sh` สร้าง control folder ที่ base — **ไม่คัดลอก tools/** (มีแค่ `STATE.md`)
แล้วรัน `init-config.sh` จาก Base เพื่อถาม services

### อยู่ใน Base ได้ไหม?

รายละเอียดต่อ session → [ต่อ session เดิม](#ต่อ-session-เดิม--เปิดโปรเจกต์ที่ตั้งค่าไว้แล้ว)

| การกระทำ | ทำจาก Base ได้? | หมายเหตุ |
| ------ | ------------- | ----- |
| `Use loop-start` / `Use loop-orch` | ได้ | ใช้ `.active-project` หรือ skill ปักเป้า |
| `node cfg.js`, `verify-paths`, `scaffold` | ไม่ได้ | ต้อง `cd` เข้า control folder (tools อ่าน config จาก cwd) |
| `dash.sh serve` / `where` | ได้ | กระดานกลาง ไม่ผูก cwd |
| `dash.sh set/reset/log` | ได้แต่ tag ผิด | ไม่มี config ใน cwd → project tag `(unknown)` |

---

## ทีม agent

| ชื่อ | บทบาท | ทำอะไร |
| ---- | ---- | ---- |
| `loop-start` | Bootstrap | เริ่มที่นี่ — เลือก/สร้างโปรเจกต์ + เขียน `loop.config.json` ส่งต่อ loop-orch |
| `loop-orch` | Orchestrator | อ่าน `STATE.md` + `loop.config.json` มอบหมายทีม รัน loop |
| `pm` | Product | แตก AC · **นำ triage** เมื่อ QA FAIL |
| `design` | Designer | UX/UI flow ทุก state ก่อน FE |
| `fe` | Frontend | UI ต่อ API ทุก state |
| `fe-anim` | Frontend (motion/3D) | animation, Three.js/WebGL |
| `be` | Backend | API, business logic, data layer |
| `be-sr` | Senior Backend | ออกแบบ DB + security review |
| `qa` | QA | AC → PASS/FAIL · FE/UI ผ่าน **`qa-browser`** (browser-use) |

**วง feedback:** QA FAIL → PM triage → ส่งกลับ `fe`/`be`/… → แก้ → QA ทดสอบใหม่ (สูงสุด 3 รอบ) — บันทึกใน `STATE.md` → `## Feedback history`

**`qa-browser`** รวมใน `zsh tools/deploy.sh` — ดู [ขั้น 1](#1-ติดตั้งทีม-ครั้งเดียวต่อเครื่อง--รันจาก-base)

สเปก loop เต็ม → [LOOP.md](LOOP.md) · อ้างอิง: [Loop Engineering Guide 2026](https://tosea.ai/blog/loop-engineering-ai-agents-complete-guide-2026)

---

## แพลตฟอร์ม (Claude Code · Cursor · Hermes)

| | Claude Code | Cursor | Hermes |
| - | ----------- | ------ | ------ |
| รูปแบบทีม | subagents | `.claude/agents` + Custom Modes | SKILL.md (slash) |
| ติดตั้ง | `zsh tools/deploy.sh` | เปิดโฟลเดอร์ | `zsh tools/deploy.sh` |
| เริ่ม | `Use loop-start` | `Use loop-start` | `/loop-start` |
| เรียก agent | `Use be to ...` | แชต / Custom Mode | `/be`, `/qa`, … |
| งานคู่ขนาน | เต็มที่ (worktree) | จำกัด | ได้ (subagents) |
| อัตโนมัติ/cron | ผ่าน loop | — | ในตัว |
| จุดเด่น | loop เต็มรูปแบบ | แก้/รีวิวด้วยมือ | headless + ตั้งเวลา |

### Claude Code

`deploy.sh` คัดลอก subagent ไป `~/.claude/agents/` — ใช้ได้ทุกโปรเจกต์ทันที

**ดึงรายละเอียดจากแชทไป dashboard อัตโนมัติ (Claude Code hooks):**

```zsh
zsh tools/install-cc-hooks.sh   # หรือรวมใน deploy.sh แล้ว
```

หลังติดตั้ง → **restart Claude Code** — hook จะส่งไป dashboard เมื่อ:
- sub-agent จบ (`SubagentStop` → ข้อความสรุปเต็มจาก `last_assistant_message`)
- แก้/สร้างไฟล์ (`Edit` / `Write`)
- รัน Bash (ยกเว้นคำสั่ง `dash.sh` เอง)

ต้องมี `loop.config.json` ใน control folder (หรือโฟลเดอร์แม่) เพื่อ tag ชื่อโปรเจกต์

```
Use loop-start
Use loop-orch at L1: ...
Use be to ...
Use qa to ...
```

**ความสามารถ:** subagent แท้ — worktree คู่ขนาน ส่งต่อ context autonomy L1–L3 ประสบการณ์ loop เต็มที่สุด

### Cursor

เปิดโฟลเดอร์ — Cursor อ่าน `.claude/agents/` อัตโนมัติ
persona เสริม (ทางเลือก): Settings → Custom Modes → วางแต่ละ `.claude/agents/*.md`

แชตเหมือน Claude Code (`Use loop-orch at L1: ...`) หรือสลับ Custom Modes

**ความสามารถ:** ดีสำหรับแก้แบบโต้ตอบ งานขนานน้อยกว่า Claude Code เหมาะแก้/รีวิวด้วยมือ

### Hermes

`deploy.sh` ติดตั้ง team skills (`loop-start loop-orch pm design fe fe-anim be be-sr qa LOOP`)
ไป `~/.hermes/skills/` พร้อม symlink external skills

```
/loop-start
/loop-orch
/be
/qa
```

รวม skills เป็น bundle:

```zsh
hermes bundles create backend-dev -s be -s be-sr -s postgres-best-practices
hermes bundles create frontend-dev -s fe -s fe-anim -s solid
```

> **ชนชื่อ `qa`:** team agent `qa` กับ browser-use skill `qa` → ตัวติดตั้งเปิดเป็น **`qa-browser`** ใน Hermes

**ความสามารถ:** autonomous/headless, cron, หลายช่องทาง เหมาะ loop ตามเวลา (เช่น triage ตอนเช้า) ต้องรันใน/ชี้ control folder ที่ถูก

> ทั้งสามแพลตฟอร์มอ่าน `loop.config.json` จาก **โฟลเดอร์ที่คุณอยู่** เริ่มด้วย `loop-start` เพื่อปักโปรเจกต์ที่ถูก

---

## loop.config.json

ห้ามสร้างใน Base — `loop-start` หรือ
`zsh "$(cat ~/.loop-base)/tools/init-config.sh"` (จาก control folder) พาไล่ให้
งานเดียวมีหลาย service ได้ **แต่ละ service อยู่ base path ของตัวเองได้**

```json
{
  "project": "my-app",
  "mode": "new",
  "autonomy": "L1",
  "services": [
    { "id": "web",     "side": "fe", "path": "web",                        "stack": "nextjs" },
    { "id": "admin",   "side": "fe", "path": "apps/admin",                 "stack": "vite-react" },
    { "id": "api",     "side": "be", "path": "api",                        "stack": "nestjs" },
    { "id": "billing", "side": "be", "path": "/Users/me/work/billing-svc", "stack": "node-express" }
  ]
}
```

### ฟิลด์ `services[]`

| ฟิลด์ | ความหมาย | ตัวอย่าง |
| ----- | ------- | -------- |
| `id` | ชื่อสั้นไม่ซ้ำสำหรับคำสั่งเช่น `scaffold-all.sh api` | `web`, `admin`, `api`, `worker` |
| `side` | agent ไหนรับผิดชอบ | `fe` = frontend/UI (fe, fe-anim) · `be` = backend/API/data (be, be-sr) |
| `path` | ตำแหน่งโค้ด — **relative** = ใต้ control folder · **absolute/`~`** = ที่ไหนก็ได้ | `web`, `apps/admin`, `~/Documents/coding/legacy/old-api` |
| `stack` | แม่แบบ scaffold | fe: `nextjs` `vite-react` `sveltekit` `astro` · be: `nestjs` `fastapi` `node-express` `go` · `""` = ไม่ scaffold |

### `mode`

| ค่า | ความหมาย |
| ----- | ------- |
| `new` | agent scaffold โฟลเดอร์ใหม่ตาม path ที่ให้ |
| `existing` | ใช้โค้ดเดิม — ไม่ scaffold (`stack` เป็น `""` ได้) |

### กฎ `path`

- **relative** (`web`, `apps/admin`) → `<control folder>/web` ฯลฯ
- **absolute** (`/Users/me/.../old-api`) → ใช้ตามนั้น ชี้ repo แยกได้
- **`~`** → ขยายเป็น home
- ผสม relative + absolute ใน config เดียวได้

ตรวจ path ที่ resolve แล้ว (จาก control folder):

```zsh
B="$(cat ~/.loop-base)"
node "$B/tools/cfg.js" resolved
node "$B/tools/cfg.js" abspath api
node "$B/tools/cfg.js" ids fe
```

### เพิ่ม service ทีหลัง

control folder สร้างครั้งเดียว — **`services[]` ขยายได้เรื่อย ๆ** ไม่ต้อง `loop-start` ใหม่

**วิธีเพิ่ม**

1. **แก้ `loop.config.json` เอง** — เพิ่ม object ใน `services[]` (ดูรูปแบบด้านบน)
2. **ผ่านแชต** — `Use loop-orch at L1: add service … to loop.config.json` (จาก control folder หรือ Loom + `.active-project`)

**อย่ารัน `init-config.sh` ซ้ำโดยไม่ระวัง** — wizard เขียนทับทั้งไฟล์ ไม่ merge service เดิม

**หลังเพิ่มแล้ว** (จาก control folder):

```zsh
B="$(cat ~/.loop-base)"
node "$B/tools/cfg.js" resolved
zsh "$B/tools/verify-paths.sh"
# mode: new + path relative ใหม่ → scaffold เฉพาะ service ที่เพิ่ม
zsh "$B/tools/scaffold-all.sh" admin
```

| หัวข้อ | หมายเหตุ |
| ----- | -------- |
| `id` | ต้องไม่ซ้ำใน config เดียวกัน |
| `path` relative | resolve จาก **control folder** |
| `path` absolute/`~` | ชี้ repo เก่าที่ไหนก็ได้ — ไม่ต้องย้ายโค้ด |
| `mode: existing` | เพิ่มแล้วใช้ได้เลย — `stack: ""` ได้ |
| `STATE.md` | ไม่ต้องแก้ — loop อ่าน config ใหม่ทุกครั้ง |

ตัวอย่างเต็ม → [loop.config.example.json](loop.config.example.json)

### พรอมต์ wizard — พิมพ์ `path` อย่างไร

เมื่อรัน `zsh tools/new-project.sh <name>` (จาก Base) หรือ
`zsh "$(cat ~/.loop-base)/tools/init-config.sh"` (ใน control folder) **`path`** รับสองรูปแบบ (`←` = สิ่งที่พิมพ์):

```text
-- new service --
  service id — short name, e.g. web/admin/api (blank = done): web        ←  service name
  side — fe (frontend/UI) or be (backend/API/data) [fe]:                  ←  Enter = fe
  path — relative (under this project) or absolute (its own base) [web]:  ←  Enter = "web" (subfolder under control)
  stack hint — fe: nextjs|... / be: ...|go [nextjs]:                      ←  Enter = nextjs

-- new service --
  service id ...: api
  side ... [fe]: be                                                       ←  type be
  path ... [api]: /Users/me/Documents/coding/legacy/old-api               ←  absolute = existing folder elsewhere
  stack ... [nestjs]:                                                     ←  Enter = nestjs (be default)

-- new service --
  service id ...:                                                         ←  blank Enter = done
```

ผลลัพธ์ — path ผสมใน config เดียว:

```json
"services": [
  { "id": "web", "side": "fe", "path": "web",                                     "stack": "nextjs" },
  { "id": "api", "side": "be", "path": "/Users/me/Documents/coding/legacy/old-api", "stack": "nestjs" }
]
```

### Legacy sync — ทำความเข้าใจโค้ดเดิมก่อน (`mode: existing`)

กับโค้ด legacy agent **ไม่มี context ก่อนหน้า** — `loop-orch` รัน **orientation (ขั้น 0b)** ก่อน clarify/build:

1. ระบุ **service ใน scope** จาก `loop.config.json` (ไม่สแกนทั้ง repo ถ้าไม่จำเป็น)
2. มอบหมาย maker (`fe` / `be` / `be-sr`) **อ่านโครงสร้าง** — stack, entry point, test, convention
3. **`/ponytail-review`** บน **ไฟล์/โมดูลที่งานนี้จะแตะ** — over-engineering / ความเสี่ยง
4. **`/ponytail-audit`** — เมื่อจำเป็นเท่านั้น (โค้ดเบสใหญ่ หนี้บล็อก หรือผู้ใช้ขอ) จำกัดโฟลเดอร์ service ที่เกี่ยว
5. สรุปใน `STATE.md` → `## Project context` + `## Relevant areas for this task`

```
loop-orch: legacy orient — shop (fe+be)
  → fe explore shop-frontend → ponytail-review on components to change
  → be explore shop-core     → ponytail-review on relevant API layer
  → write STATE.md, then PM / build
```

ต้องมี `ponytail-review` / `ponytail-audit` — `deploy.sh` ติดตั้งให้ — ดู [ขั้น 1](#1-ติดตั้งทีม-ครั้งเดียวต่อเครื่อง--รันจาก-base)

### ระดับ autonomy

| ระดับ | ความหมาย |
| ----- | ------- |
| **L1 — report only** | วางแผน/เสนอ ไม่ commit — **เริ่มที่นี่** |
| **L2 — assisted** | maker เขียนใน worktree คุณรีวิวแล้ว merge |
| **L3 — unattended** | อัตโนมัติเต็มเมื่อไว้ใจ — safety denylist ใช้เสมอ |

**L3 ใน Claude Code — ไม่ต้องกด Yes ทุกคำสั่ง:** `autonomy: "L3"` ใน config อย่างเดียวไม่พอ — ติดตั้ง hook ครั้งเดียว:

```zsh
zsh tools/install-l3-hooks.sh          # จาก Loom blueprint
cd <control-folder> && zsh "$(cat ~/.loop-base)/tools/apply-l3-claude-settings.sh"
```

แล้ว **restart Claude Code** — compound `cd … && git …` จะ auto-allow (ยกเว้น denylist: force-push, `rm -rf`, `.env`, deploy)

ขยับขึ้นทีละระดับเมื่อระดับก่อนหน้า "น่าเบื่อ" (ไม่มีเซอร์ไพรส์) รายละเอียดใน [LOOP.md](LOOP.md)

---

## ตัวอย่าง: ห่อโฟลเดอร์เดิมเป็น services (`mode: existing`)

> โครงโฟลเดอร์ (`legacy/` + control ใต้ `agent-build/`) อยู่ [ด้านบน](#ตัวอย่าง-โค้ดอยู่ที่หนึ่ง-control-อยู่อีกที่) — ส่วนนี้เป็นขั้นตั้งค่าเต็ม

โค้ด legacy ใต้ `~/Documents/coding/legacy/` — ห่อโฟลเดอร์เป็นงาน
**โดยไม่ย้าย/คัดลอกโค้ด** — `path` absolute + `mode: existing`

> control folder ใหม่ใต้ base โค้ดจริงอยู่ที่เดิม
> 1 งาน = 1 control folder = session แยกได้

### งาน A — shop (2 services)

```zsh
zsh tools/new-project.sh shop          # control ใหม่ที่ base, wizard mode=existing
```

```json
{
  "project": "shop",
  "mode": "existing",
  "autonomy": "L1",
  "services": [
    { "id": "frontend", "side": "fe", "path": "/Users/me/Documents/coding/legacy/shop-frontend", "stack": "" },
    { "id": "core",     "side": "be", "path": "/Users/me/Documents/coding/legacy/shop-core",     "stack": "" }
  ]
}
```

### งาน B — portal session แยก (3 services)

```zsh
zsh tools/new-project.sh portal
```

```json
{
  "project": "portal",
  "mode": "existing",
  "autonomy": "L1",
  "services": [
    { "id": "client",      "side": "fe", "path": "/Users/me/Documents/coding/legacy/portal-client", "stack": "" },
    { "id": "core",        "side": "be", "path": "/Users/me/Documents/coding/legacy/portal-core",   "stack": "" },
    { "id": "data-client", "side": "be", "path": "/Users/me/Documents/coding/legacy/portal-data",   "stack": "" }
  ]
}
```

> `side` ส่งงานไป agent ที่ถูก (fe/fe-anim กับ be/be-sr) — ปรับตามจริง
> `stack` เป็น `""` ได้สำหรับ existing (ไม่ scaffold)

ตรวจก่อนเริ่ม:

```zsh
cd ~/Documents/coding/agent-build/shop
B="$(cat ~/.loop-base)"
node "$B/tools/cfg.js" resolved
zsh "$B/tools/verify-paths.sh"
```

### ผ่าน skill — `/loop-start` หรือ `Use loop-start`

ไม่ต้องใช้ `zsh tools` — แชตทีละขั้น skill เขียน `loop.config.json` (existing + absolute paths) ที่ control folder

```text
You: Use loop-start                                    ← Step 1 เริ่ม
loop-start: Where should projects live? [~/Documents/coding/agent-build]
You: (Enter)                                           ← Step 1: ยืนยัน base (mkdir ถ้ายังไม่มี)
loop-start: Existing projects: (none) — (1) open existing  (2) create new
You: 2                                                 ← Step 2b: สร้าง control ใหม่
loop-start: Project name?
You: shop                                              ← ชื่อ control folder → …/agent-build/shop/
loop-start: mode? new = scaffold / existing = use code you already have
You: existing
loop-start: autonomy? [L1]
You: (Enter)
loop-start: service — id / side / path / stack (blank = done)
You: frontend · fe · ~/Documents/coding/legacy/shop-frontend · (blank)
You: core · be · ~/Documents/coding/legacy/shop-core · (blank)
You: (blank Enter = done)                              ← Step 2b: เขียน loop.config.json + STATE.md
loop-start: ✓ Active project → ~/Documents/coding/agent-build/shop   ← Step 3: .active-project
            wrote loop.config.json — next: Use loop-orch at L1: <task>
```

`loop.config.json` เหมือนงาน A ด้านบน

> ผลลัพธ์เดียวกัน: `new-project.sh`/`init-config.sh` (terminal) กับ `loop-start` (แชต)
> แพลตฟอร์มแชตอย่างเดียว (Hermes/Claude) → `/loop-start` สะดวกสุด

### ต่อ session เดิม — เปิดโปรเจกต์ที่ตั้งค่าไว้แล้ว

ความจำของ loop อยู่ใน `STATE.md` ของ control folder (`loop.config.json` ด้วย)
**ไม่ต้องสร้างใหม่** — ชี้กลับ control folder เดิม

#### วิธีหลัก — อยู่ใน Loom (ไม่ต้อง `cd` เอง)

เปิด Cursor/แชตใน **Loom** (repo พิมพ์เขียวนี้) แล้วพิมพ์:

```
Use loop-start
```

ตัวอย่างบทสนทนา:

```
You:        Use loop-start                            ← Step 1 เริ่ม
loop-start: Where should projects live?
You:        ~/Documents/coding/agent-build          ← Step 1: ยืนยัน base (mkdir ถ้ายังไม่มี)
loop-start: Found existing projects:
              1) shop   → .../agent-build/shop
              2) portal → .../agent-build/portal
            Open existing or create new?
You:        1                                          ← Step 2a: เปิด control เดิม (ไม่สร้างโฟลเดอร์)
loop-start: ✓ Active project → .../agent-build/shop   ← Step 3: .active-project
            read STATE.md — continue with:
            Use loop-orch at L1: <work to resume>
You:        Use loop-orch at L1: continue from STATE — fix checkout bug
```

`loop-start` / `/loop-start` จะ:
- **Step 1** — สร้าง **base folder** ถ้ายังไม่มี (`mkdir -p`)
- **Step 2a** — แสดง control ใต้ base ที่มี `loop.config.json` — **ไม่สร้างโฟลเดอร์ใหม่**
- **Step 2b** — สร้าง **control folder** + config (ข้าม wizard ไม่ได้)
- **Step 3** — เขียน `.active-project` ใน Loom ให้ `loop-orch` รู้งานที่ active

ทำต่อได้ทันที — **อยู่แชต Loom** เพราะ `loop-orch` อ่าน `.active-project` เมื่อ cwd ไม่มี config:

```
Use loop-orch at L1: <continue task>
```

Hermes: `/loop-orch run at L1: <task>`

#### เมื่อไหร่ต้อง `cd`?

| การกระทำ | ต้อง `cd`? |
| ------ | ---------- |
| `Use loop-start` / `Use loop-orch` ในแชต | **ไม่** — ใช้ `.active-project` |
| `verify-paths`, `scaffold`, `init-config`, `node cfg.js` | **ใช่** — tools อ่าน `loop.config.json` จาก cwd |
| `dash.sh serve` / `where` | **ไม่** — กระดานกลาง |
| `dash.sh set/reset/log` | แนะนำ `cd` เข้า control — ไม่งั้น project tag `(unknown)` |

แนะนำเปิดโฟลเดอร์ใน IDE — เปิด **control folder** เป็น workspace แล้ว `Use loop-orch` (cwd มี `loop.config.json`):

```zsh
# Optional — open control as Cursor workspace
# File → Open Folder → ~/Documents/coding/agent-build/shop
# chat: Use loop-orch at L1: <task>
```

หรือ `cd` ใน terminal สำหรับเครื่องมือ manual:

```zsh
cd ~/Documents/coding/agent-build/shop
B="$(cat ~/.loop-base)"
zsh "$B/tools/verify-paths.sh"
```

#### สลับงาน (`shop` ↔ `portal`)

รัน `Use loop-start` อีกครั้ง → เลือก control อื่น — หรือ `cd` แล้วเรียก orch
ทุกแพลตฟอร์มใช้ `loop.config.json` ของโปรเจกต์ที่ active — ไม่ปนกัน

#### เครื่องใหม่ / ยังไม่เคย deploy

ครั้งเดียวจาก Loom:

```zsh
zsh tools/deploy.sh    # register ~/.loop-base
```

จากนั้น `Use loop-start` ตามปกติ — control folder + `STATE.md` ยังอยู่บนดิสก์ตาม path เดิม

---

## กระดานสถานะ

กระดานกลางที่ Base (`agent-dashboard/`) — **ไม่คัดลอกไปปลายทาง**
ทุกโปรเจกต์/session รายงานที่นี่ แต่ละบรรทัด log มี tag ชื่อโปรเจกต์

```zsh
# Open board (from anywhere)
zsh tools/dash.sh serve          # Star-Office pixel office → http://localhost:19000
zsh tools/dash.sh where          # central board path

# Report status (from control folder for correct project tag)
B="$(cat ~/.loop-base)"
zsh "$B/tools/dash.sh" reset "<task title>"           # new task (keeps cross-project history)
zsh "$B/tools/dash.sh" set orch work "planning" "received task"
zsh "$B/tools/dash.sh" set pm   done "AC ready"
zsh "$B/tools/dash.sh" set be   work "build /auth"
zsh "$B/tools/dash.sh" loop 2                     # QA sent work back, round 2
zsh "$B/tools/dash.sh" set qa   done "PASS all criteria"
```

**Activity feed ละเอียด** — ใครคุยกับใคร · skill อะไร · คำสั่งอะไร · กำลังทำอะไร:

```zsh
zsh "$B/tools/dash.sh" delegate orch pm "→ PM: write AC" activity="planning loop" skill=loop-orch
zsh "$B/tools/dash.sh" skill be ponytail activity="trimming auth handler"
zsh "$B/tools/dash.sh" cmd qa "npx playwright test" activity="regression" skill=qa-browser
zsh "$B/tools/dash.sh" event orch "route fixes" kind=delegate to=be cmd="Task be" activity="triage"
zsh "$B/tools/dash.sh" say besr title="ผลตรวจ core" kind=report --stdin <<'EOF'
TL;DR summary + decisions + PASS/FAIL here
EOF
```

คำสั่ง: `say` (บทความยาว/multiline) · `delegate` · `skill` · `cmd` · `event` · `log` · `set`
feed เก็บ 500 บรรทัด · Star-Office มี panel **Loop Activity** + bubble จาก log จริง

เปิดอัตโนมัติตอน `deploy.sh` · ตอนเริ่ม `loop-orch` จะถาม **「เปิด dashboard ดู agent ทำงานไหม? [Y/n]」** (default Y) แล้วเปิด browser ที่ `http://localhost:19000` — เรียกซ้ำได้ปลอดภัย

**Star-Office dashboard** (`agent-dashboard/star-office/`) — vendored จาก
**[Star-Office-UI](https://github.com/ringhyacinth/Star-Office-UI)** โดย [ringhyacinth](https://github.com/ringhyacinth)
โค้ด **MIT**; **asset ศิลปะใช้เรียนรู้แบบไม่เชิงพาณิชย์เท่านั้น** (ดู LICENSE ต้นทาง)
Loom เพิ่ม: `star-office-bridge.js`, panel Loop Activity, `cc-dash-bridge.js` (Claude Code → กระดาน), และคำสั่ง feed ใน `agent-status.js` (`file`, `report`, `wait`, …)
- `star-office-bridge.js` สะท้อน loop `status.json` → office + `activity.json` (`GET /activity`)
- panel **Loop Activity** แสดง delegate / skill / cmd / **say** (เต็มความยาว) · guest bubble จาก log จริง
- **Yesterday memo ถอดออก** — พื้นที่ให้ activity feed กว้างขึ้น
- ตัวละคร 8 บทบาทในโซน (orch = หลัก คนอื่นเป็น guest)
- ป้าย office = ชื่อโปรเจกต์
- รันครั้งแรกสร้าง venv เล็ก + ติดตั้ง flask

---

## คำสั่งที่ใช้บ่อย

tools อยู่แค่ใน Base — รัน **จาก control folder** (ให้ tools อ่าน `loop.config.json` ใน cwd)
แต่ชี้สคริปต์ไป Base ผ่าน `~/.loop-base`:

```zsh
cd ~/Documents/coding/agent-build/my-app      # enter control folder first
B="$(cat ~/.loop-base)"                        # Base path (written by deploy.sh)

node "$B/tools/cfg.js" resolved      # services + resolved absolute paths
node "$B/tools/cfg.js" get project   # read scalar config value
node "$B/tools/cfg.js" abspath api   # absolute path for service id=api
zsh "$B/tools/verify-paths.sh"      # check folder access / prep create (mode new)
zsh "$B/tools/scaffold-all.sh"      # scaffold all services
zsh "$B/tools/scaffold-all.sh" api  # scaffold service id=api only
zsh "$B/tools/dash.sh" serve        # open central board
zsh "$B/tools/dash.sh" where        # central board path
```

รันจาก Base โดยตรง (ไม่มี config ใน cwd):

```zsh
zsh tools/deploy.sh                 # install team + register ~/.loop-base
zsh tools/loop-start.sh                 # wizard Steps 1–4
zsh tools/new-project.sh my-app       # shortcut: Step 1 + 2b
zsh tools/sync-agents.sh              # sync agent defs to all platforms
zsh tools/dash.sh serve               # open board
```

> ใช้ **chat skills** (`loop-start`, `loop-orch`, …) หรือ `zsh tools/*.sh` / `zsh "$B/tools/*.sh"`

---

## เครดิตและขอบคุณ

### Dashboard

| ส่วน | เครดิต |
| ---- | ------ |
| Pixel office UI | **[Star-Office-UI](https://github.com/ringhyacinth/Star-Office-UI)** — [ringhyacinth](https://github.com/ringhyacinth) โค้ด MIT; asset ศิลปะ **ใช้เรียนรู้แบบไม่เชิงพาณิชย์เท่านั้น** |
| การเชื่อมกับ Loop | `star-office-bridge.js`, `agent-status.js`, `cc-dash-bridge.js`, `l3-permission-hook.js` — อยู่ใน repo นี้ |

### Skills ที่มากับ Loom (`hermes-skills/`)

สร้างสำหรับทีมนี้ (ติดตั้งไป `~/.hermes/skills/` โดย `deploy.sh`):

`loop-start` · `loop-orch` · `pm` · `design` · `fe` · `fe-anim` · `be` · `be-sr` · `qa` · `LOOP`

### External skills (`tools/install-external-skills.sh`)

ติดตั้งไป `~/.agents/skills/` ตอน deploy (ผ่าน `npx skills add` ถ้ามี):

| Skill | ใช้โดย | หมายเหตุ |
| ----- | ------- | -------- |
| **solid** | makers ทุกฝั่ง | SOLID, TDD, clean code |
| **ponytail** · **ponytail-review** · **ponytail-audit** | makers ทุกฝั่ง | โค้ดน้อยที่สุดที่ถูก; review / audit — [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |
| **postgres-best-practices** | be-sr | แนวทาง Postgres |
| **docker-containerization** | ทุก agent | [ailabs-393/ai-labs-claude-skills](https://skills.sh/ailabs-393/ai-labs-claude-skills/docker-containerization) |
| **hexagonal-architecture** | be, be-sr | Ports & Adapters — [affaan-m/ECC](https://github.com/affaan-m/ECC/blob/main/skills/hexagonal-architecture/SKILL.md) |
| **perf-lighthouse** | fe | Lighthouse audit |
| **threejs-animation** | fe-anim | Three.js animation |
| **qa** → Hermes **`qa-browser`** | qa | ทดสอบเบราว์เซอร์ — [browser-use/browser-use](https://github.com/browser-use/browser-use) (`tools/install-browser-use-qa.sh`) |

### Skills แนะนำ (ติดตั้งเอง — agent อ้างอิง)

| Skill | ใช้โดย | แหล่ง / ติดตั้ง |
| ----- | ------- | ---------------- |
| **context7** | fe, be, fe-anim, be-sr | MCP — เอกสาร library ล่าสุด |
| **ui-ux-pro-max** | design | design intelligence / UI spec |
| **pm-skills** | pm | [phuryn/pm-skills](https://github.com/phuryn/pm-skills) marketplace |
| **threejs-skills** | fe-anim | CloudAI-X Three.js skill bundle |
| **handoff** | ทุกตัว | ต่อ session / IDE |
| **docx** · **pdf** · **pptx** · **xlsx** | pm, design, qa, orch | deliverable เมื่อผู้ใช้ขอ |

### แนวทาง loop

วง loop อิง durable-state agent loops — ดู [LOOP.md](LOOP.md) และ [Loop Engineering Guide 2026](https://tosea.ai/blog/loop-engineering-ai-agents-complete-guide-2026)

---

## โครง repo Base

```
.claude/agents/            9 agents — source of truth (Claude Code global, Cursor reads in-project)
hermes-skills/             SKILL.md for Hermes (generated via to-hermes-skills.sh)
agent-dashboard/           **central** live status board (Star-Office — all projects report here)
tools/                     only in Base — every control folder shares via ~/.loop-base
  deploy.sh                install team to Claude Code + Hermes + register Base at ~/.loop-base
  sync-agents.sh           sync agent defs to all platforms (source = .claude/agents/)
  loop-start.sh              wizard Steps 1–4: base folder → control folder → .active-project → hand off
  new-project.sh             shortcut: loop-start --new NAME (Step 1 + 2b)
  base-dir.sh              resolve destination folder (arg > BASE_DIR > .base-dir > default)
  init-config.sh           wizard writes loop.config.json (run in control folder)
  dash.sh                  talk to central board (serve / set / log) — auto-tags project name
  scaffold-all.sh · scaffold.sh   scaffold services per config (mode=new)
  cfg.js · verify-paths.sh        read config (from cwd) / verify folder access
  to-hermes-skills.sh · install-hermes-skills.sh   build + install SKILL.md for Hermes
LOOP.md                    loop methodology (also a skill)
STATE.template.md          loop memory template (copied to STATE.md in control folder)
loop.config.example.json   example config with _help for every field
```
