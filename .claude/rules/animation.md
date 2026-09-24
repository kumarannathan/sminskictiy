# Animation Rules

## Animation Philosophy

Animations should make the Smiski feel alive without becoming overly
cartoonish.

Movement should be:

- soft
- slightly bouncy
- physical
- readable
- expressive

---

# Core Animations

Required:

- Idle
- Walk
- Run
- Jump
- Fall
- Land
- Sit
- Stand
- Climb
- Hang
- Push
- Pull
- Carry
- Use Object
- Wave
- Sleep
- Ragdoll
- Get Up

---

# Animation + IK

Animations provide the primary body motion.

IK adapts the character to the environment.

Do not create separate animations for every possible surface.

Example:

One climbing animation + IK targets

rather than:

LadderClimbAnimation
FenceClimbAnimation
FireEscapeClimbAnimation
WallClimbAnimation

---

# Physicality

Animations should allow room for procedural adjustments.

Avoid animation poses that make IK impossible.

Hands and feet should have clear, predictable contact positions.

---

# Transitions

Avoid abrupt state changes.

Important transitions:

Idle → Walk
Walk → Run
Run → Stop
Run → Jump
Jump → Land
Fall → Ragdoll
Ragdoll → Get Up
Walk → Sit
Sit → Stand
