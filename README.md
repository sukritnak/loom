# AI Agent Office — พิมพ์เขียวกลาง (control-repo blueprint)

ทีม AI 8 ตัวที่ทำงานเป็น **loop** (วางแผน → สร้าง → ตรวจ → วน) ใช้ได้ทั้ง
**Claude Code · Cursor · Hermes**

> repo นี้คือ **ตัวกลาง/พิมพ์เขียว** — ไม่ใช่ที่เก็บโค้ดงานจริง
> โปรเจกต์จริงถูกสร้างที่ `~/Documents/coding/agent-build/<ชื่อโปรเจกต์>`
> และ `loop.config.json` จะอยู่ที่ **โปรเจกต์ปลายทาง** ไม่ใช่ใน repo นี้

---

## เริ่มใช้ใน 3 ขั้น

เริ่มจากคำสั่งเดียว — เป็น wizard ถามทีละขั้นใน terminal:

```bash
make loop-start
```

มันจะไล่ถามให้เอง:

1. **Deploy?** — ติดตั้ง/รีเฟรชทีมเข้า Claude Code + Hermes (เลือก y/n เอง)
2. **Base folder** — กด Enter ใช้ค่า default หรือพิมพ์ path เอง (ไม่ต้องใส่ `DIR=`) ถ้าโฟลเดอร์ยังไม่มีจะถามสร้างให้
3. **โปรเจกต์** — เลือกจากรายการที่เคยทำ / สร้างใหม่ (ถาม name + services) / เปิดของเดิมด้วย path เต็ม
4. ปักหมุด `.active-project` แล้วพิมพ์คำสั่ง `Use loop-orch ...` ที่ชี้ไป `loop.config.json` ตัวที่ถูก

จากนั้น `cd` เข้าโปรเจกต์ แล้วสั่งงานทีมในแพลตฟอร์มไหนก็ได้:

```
Use loop-orch at L1: เพิ่มฟีเจอร์รีเซ็ตรหัสผ่านทางอีเมล
```

### คำสั่งย่อย (ถ้าไม่อยากใช้ wizard)

```bash
make deploy                     # ติดตั้งทีมเข้าแพลตฟอร์ม (ครั้งเดียว/ต่อเครื่อง)
make set-base DIR=~/work/proj   # ตั้งโฟลเดอร์ปลายทางถาวร (absolute & นอก repo)
make new-project NAME=my-app    # สร้างโปรเจกต์ + wizard services (ไม่ปักหมุด)mmm
make start NAME=my-app          # สร้างถ้ายังไม่มี + ปักหมุด + พิมพ์คำสั่ง
make start                      # ใช้โปรเจกต์ที่ปักหมุดล่าสุด
make list-project               # ดูโปรเจกต์ทั้งหมดที่เคยทำ + ตัวที่ active
```

loop-orch จะเช็ก `loop.config.json` ในโฟลเดอร์ปัจจุบันก่อน ถ้าไม่เจอจะอ่าน `.active-project` (กันแก้ผิดโปรเจกต์)

---

## ทีม 8 ตัว (เรียกด้วยชื่อสั้น)


| ชื่อเรียก   | บทบาท                | ทำอะไร                                                      |
| ----------- | -------------------- | ----------------------------------------------------------- |
| `loop-orch` | Orchestrator         | อ่าน `STATE.md` + `loop.config.json` แล้วสั่งงานทีม วน loop |
| `pm`        | Product              | แตกโจทย์เป็น acceptance criteria                            |
| `design`    | Designer             | UX/UI flow, ระบุทุก state ก่อนส่ง FE                        |
| `fe`        | Frontend             | เขียน UI ต่อ API จัดการทุก state                            |
| `fe-anim`   | Frontend (motion/3D) | animation, Three.js/WebGL                                   |
| `be`        | Backend              | API, business logic, data layer                             |
| `be-sr`     | Senior Backend       | DB design + security review                                 |
| `qa`        | QA                   | ตรวจกับ acceptance criteria → PASS/FAIL                     |


ดูวิธีการของ loop แบบเต็มได้ใน `[LOOP.md](LOOP.md)`

---

## ใช้ในแต่ละแพลตฟอร์ม

**Claude Code** — `make deploy` คัดลอก subagents ไป `~/.claude/agents/` ใช้ได้ทุกโปรเจกต์
เรียกด้วย `Use loop-orch at L1: ...` หรือ subagent อื่นตามชื่อ

**Cursor** — เปิดโฟลเดอร์โปรเจกต์ Cursor อ่าน `.claude/agents/` ให้อัตโนมัติ
อยากได้ persona แยก: Settings → Custom Modes → เพิ่มทีละตัว วางเนื้อหาจาก `.claude/agents/*.md`

**Hermes** — `make deploy` ติดตั้ง 9 skill (`loop-orch pm design fe fe-anim be be-sr qa LOOP`)
ไป `~/.hermes/skills/` พร้อม symlink skill ภายนอก
เรียกด้วย slash command เช่น `/loop-orch`, `/be`

> **ชนชื่อ `qa`:** ทีมนี้มี agent ชื่อ `qa` ส่วน browser-use ก็มี skill ชื่อ `qa`
> ตัวติดตั้งจึงตั้ง browser-use เป็น `qa-browser` ใน Hermes เพื่อไม่ให้ทับกัน

---

## `loop.config.json` — สร้างที่ปลายทาง ไม่ต้องเขียนเอง

ไม่ต้องสร้างไฟล์นี้ใน repo พิมพ์เขียว — `make new-project` (หรือ `make setup` ในโปรเจกต์)
จะถามทีละขั้นแล้วเขียนให้ที่โปรเจกต์ปลายทาง path ของแต่ละ service อ้างอิงจากรากโปรเจกต์นั้น
ตัวอย่างดูที่ `[loop.config.example.json](loop.config.example.json)`

ระดับความเป็นอิสระ (autonomy): **L1** รายงานอย่างเดียว · **L2** ช่วยเขียน (ไม่ merge) · **L3** อัตโนมัติ
เริ่มที่ L1 เสมอ ขยับขึ้นเมื่อมั่นใจ

---

## โครงไฟล์ใน repo นี้

```
.claude/agents/            8 agents — แหล่งต้นทาง (Claude Code ใช้ได้ทันที)
hermes-skills/             SKILL.md สำหรับ Hermes (สร้างด้วย to-hermes-skills.sh)
agent-dashboard/           กระดานสถานะสด (index.html, agent-status.js, serve.sh)
tools/
  loop-start.sh            wizard เริ่มต้น (deploy? → base → new/existing → ปักหมุด)
  deploy.sh                ติดตั้งทีมไป Claude Code + Hermes
  base-dir.sh              resolve โฟลเดอร์ปลายทาง (arg > BASE_DIR > .base-dir > default)
  new-project.sh           สร้างโปรเจกต์จริงที่ base + เขียน loop.config.json
  start-loop-orch.sh       ปักหมุดโปรเจกต์ปลายทาง (.active-project) + พิมพ์คำสั่ง loop-orch
  init-config.sh           wizard เขียน loop.config.json (รันที่โปรเจกต์)
  cfg.js · scaffold.sh · verify-paths.sh
  to-hermes-skills.sh · install-hermes-skills.sh
Makefile                   make deploy | new-project | setup | init | dashboard ...
LOOP.md                    วิธีการของ loop (เป็น skill ด้วย)
STATE.template.md          แม่แบบความจำของ loop (คัดลอกเป็น STATE.md ที่ปลายทาง)
loop.config.example.json   ตัวอย่าง config
```

## external skills (ทางเลือก)

```bash
npx skills add solid ponytail ponytail-review perf-lighthouse \
  postgres-best-practices docker-containerization threejs-animation qa
```

---

# คู่มือฉบับอ่านเอง (ภาษาไทย)

> ส่วนนี้สำหรับคนใช้งานอ่านเอง ไม่ได้ส่งให้ agent — อธิบายวิธีใช้แต่ละแพลตฟอร์มและความต่าง

## ภาพรวมแนวคิด

repo นี้เป็น **พิมพ์เขียวกลาง (control-repo)** ทำหน้าที่ 2 อย่าง

1. **เก็บนิยามทีม** 8 ตัว (ใน `.claude/agents/`) เป็นต้นทางเดียว
2. **deploy** ทีมไปยังแพลตฟอร์ม + **bootstrap** โปรเจกต์งานจริง

งานจริงไม่ได้อยู่ใน repo นี้ — อยู่ที่ `<base-dir>/<project>/` (ดีฟอลต์ `~/Documents/coding/agent-build`)
ตั้งโฟลเดอร์ปลายทางเองได้: `make set-base DIR=/path` หรือ env `BASE_DIR=/path` (ลำดับ: arg > `BASE_DIR` > `.base-dir` > ดีฟอลต์)
ต้องเป็น **absolute path และอยู่นอก repo นี้** — ห้ามใช้ current directory / โฟลเดอร์พิมพ์เขียว (กันสร้างโปรเจกต์ทับตัวเอง)
โดยแต่ละโปรเจกต์มี `loop.config.json` + infra (Makefile, tools, dashboard) ของตัวเอง
ส่วน agents ติดตั้งที่ระดับเครื่อง (`~/.claude/agents`, `~/.hermes/skills`) จึงเรียกได้จากทุกโปรเจกต์

```
พิมพ์เขียว (repo นี้)              โปรเจกต์ปลายทาง (~/Documents/coding/agent-build/my-app)
─────────────────────             ──────────────────────────────────────────────
.claude/agents/ (ต้นทาง)   ──┐    loop.config.json   ← service map (สร้างที่นี่)
hermes-skills/             ──┤    STATE.md           ← ความจำของ loop
tools/, Makefile, LOOP.md  ──┘    Makefile, tools/, agent-dashboard/  (คัดลอกมา)
   │  make deploy → ติดตั้ง agents ระดับเครื่อง       web/ admin/ api/ ...  ← โค้ดจริง
   │  make new-project → สร้างโฟลเดอร์ปลายทาง
   └  make start → ปักหมุดว่ากำลังทำโปรเจกต์ไหน
```

## 1. Claude Code

**ติดตั้ง:** `make deploy` คัดลอก subagents 8 ตัวไป `~/.claude/agents/` ใช้ได้ทุกโปรเจกต์ทันที

**ใช้งาน:** เปิดโฟลเดอร์โปรเจกต์ปลายทางใน Claude Code แล้วพิมพ์

```
Use loop-orch at L1: เพิ่มระบบ login ด้วย Google
```

หรือเรียก subagent ตรง ๆ: `Use be to ...`, `Use qa to ...`

**ความสามารถ:** subagent แท้ — แตกงานขนานใน worktree, ส่งต่อ context กันได้, autonomy L1–L3 ครบ
เป็นแพลตฟอร์มที่ loop ทำงานเต็มรูปแบบที่สุด

## 2. Cursor

**ติดตั้ง:** เปิดโฟลเดอร์โปรเจกต์ — Cursor อ่าน `.claude/agents/` ให้อัตโนมัติ (ไม่ต้องตั้งค่าเพิ่ม)
อยากได้ persona แยกชัด: Settings → Custom Modes → เพิ่มทีละตัว วางเนื้อหาจาก `.claude/agents/*.md`

**ใช้งาน:** พิมพ์ในแชตเหมือน Claude Code (`Use loop-orch at L1: ...`)
หรือสลับ Custom Mode ที่สร้างไว้

**ความสามารถ:** ดีสำหรับงานโต้ตอบ + แก้ทีละไฟล์เห็นภาพ การแตกงานขนานหลายตัวพร้อมกัน
ทำได้จำกัดกว่า Claude Code (โมเดล agent เดียวต่อแชต) เหมาะเป็นที่ลงมือแก้/รีวิว

## 3. Hermes

**ติดตั้ง:** `make deploy` ติดตั้ง 9 skill (`loop-orch pm design fe fe-anim be be-sr qa LOOP`)
ไป `~/.hermes/skills/` + symlink skill ภายนอกอัตโนมัติ

**ใช้งาน:** เรียกด้วย slash command — `/loop-orch`, `/be`, `/qa` ฯลฯ
รวม skill เป็น bundle ได้ เช่น

```bash
hermes bundles create backend-dev -s be -s be-sr -s postgres-best-practices
hermes bundles create frontend-dev -s fe -s fe-anim -s solid
```

**ชนชื่อ `qa`:** ทีมมี agent ชื่อ `qa` และ browser-use ก็มี skill ชื่อ `qa`
ตัวติดตั้งจึงตั้ง browser-use เป็น `**qa-browser`** ใน Hermes ไม่ให้ทับกัน

**ความสามารถ:** รันแบบ autonomous/headless ได้, ตั้ง cron/automation, ต่อแชตหลายช่องทาง
เหมาะกับงานวนอัตโนมัติเป็นรอบ (เช่น triage ทุกเช้า) แต่ต้องรันใน/ชี้ไปโฟลเดอร์โปรเจกต์ที่ถูก

## เทียบความต่าง


|                | Claude Code         | Cursor                          | Hermes              |
| -------------- | ------------------- | ------------------------------- | ------------------- |
| รูปแบบทีม      | subagents           | `.claude/agents` + Custom Modes | SKILL.md (slash)    |
| ติดตั้ง        | `make deploy`       | เปิดโฟลเดอร์                    | `make deploy`       |
| เรียก          | `Use loop-orch ...` | แชต / Custom Mode               | `/loop-orch`        |
| แตกงานขนาน     | เต็มที่ (worktree)  | จำกัด                           | ได้ (subagents)     |
| อัตโนมัติ/cron | ผ่าน loop           | —                               | ในตัว               |
| จุดเด่น        | loop เต็มรูปแบบ     | ลงมือแก้/รีวิว                  | headless + ตั้งเวลา |


> ทั้ง 3 แพลตฟอร์มอ่านงานจาก `loop.config.json` ของ **โฟลเดอร์ที่กำลังเปิด/รันอยู่** เสมอ
> ใช้ `make start` ปักหมุดก่อนทุกครั้งเพื่อกันแก้ผิดโปรเจกต์

## ระดับ autonomy

- **L1 — report only:** วางแผน/เสนอ ไม่ commit (เริ่มที่นี่เสมอ)
- **L2 — assisted:** maker เขียนโค้ดใน worktree เรารีวิวแล้ว merge เอง
- **L3 — unattended:** อัตโนมัติเต็ม เปิดเองเมื่อมั่นใจ — safety denylist ยังคงอยู่ทุกระดับ

ขยับขึ้นทีละขั้นเมื่อระดับก่อนหน้า "น่าเบื่อ" (ไม่มีเซอร์ไพรส์) มาสักพัก รายละเอียดดู `LOOP.md`

## งานประจำที่ใช้บ่อย

```bash
# ในโปรเจกต์ปลายทาง
make config        # ดู services + path ที่ resolve แล้ว
make verify        # เช็กว่าโฟลเดอร์เข้าถึงได้ / เตรียมสร้าง (โหมด new)
make init          # scaffold ทุก service
make dev SVC=api   # รัน dev server ของ service เดียว
make dashboard     # เปิดกระดานสถานะสด
make status        # ดู status.json ปัจจุบัน
```

> dashboard เปิดให้อัตโนมัติอยู่แล้วทั้งตอน `make deploy` และตอนเริ่ม `loop-orch` (เด้ง browser ที่
> `http://localhost:8787` ทันที) — `serve.sh` เรียกซ้ำได้ปลอดภัย ถ้าเปิดอยู่แล้วจะแค่โฟกัส browser

