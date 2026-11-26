const STATIC = 0;
const KINEMATIC = 1;
const DYNAMIC = 2;
const ALL_BITS = 0xffffffffffffffffn;
const CELL_SIZE = 1.2;
const CONTACT_SLOP = 0.003;
const SLEEP_TIME = 0.6;
const EXPLOSION_IMPULSE_SCALE = 12;
const BODY_BYTES = 8;
const TRANSFORM_BYTES = 28;

function number(value, fallback = 0) {
  return Number.isFinite(value) ? value : fallback;
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value));
}

function readVector(view, ptr) {
  return [number(view.getFloat32(ptr, true)), number(view.getFloat32(ptr + 4, true)),
    number(view.getFloat32(ptr + 8, true))];
}

function writeVector(view, ptr, x, y, z) {
  view.setFloat32(ptr, x, true);
  view.setFloat32(ptr + 4, y, true);
  view.setFloat32(ptr + 8, z, true);
}

function setRotation(body, x, y, z, w) {
  const length = Math.sqrt(x * x + y * y + z * z + w * w);
  const scale = length > 0 ? (w < 0 ? -1 : 1) / length : 0;
  body.qx = x * scale;
  body.qy = y * scale;
  body.qz = z * scale;
  body.qw = length > 0 ? w * scale : 1;
}

function readRotation(view, ptr, target) {
  setRotation(target, number(view.getFloat32(ptr, true)), number(view.getFloat32(ptr + 4, true)),
    number(view.getFloat32(ptr + 8, true)), number(view.getFloat32(ptr + 12, true), 1));
}

function writeTransform(view, ptr, body) {
  writeVector(view, ptr, body?.x ?? 0, body?.y ?? 0, body?.z ?? 0);
  view.setFloat32(ptr + 12, body?.qx ?? 0, true);
  view.setFloat32(ptr + 16, body?.qy ?? 0, true);
  view.setFloat32(ptr + 20, body?.qz ?? 0, true);
  view.setFloat32(ptr + 24, body?.qw ?? 1, true);
}

function rotationMatrix(m, x, y, z, w) {
  const xx = 2 * x * x, yy = 2 * y * y, zz = 2 * z * z;
  const xy = 2 * x * y, xz = 2 * x * z, yz = 2 * y * z;
  const wx = 2 * w * x, wy = 2 * w * y, wz = 2 * w * z;
  m[0] = 1 - yy - zz; m[1] = xy + wz;     m[2] = xz - wy;
  m[3] = xy - wz;     m[4] = 1 - xx - zz; m[5] = yz + wx;
  m[6] = xz + wy;     m[7] = yz - wx;     m[8] = 1 - xx - yy;
}

function updateShapes(body) {
  const m = body.axes;
  const { qx, qy, qz, qw } = body;
  rotationMatrix(m, qx, qy, qz, qw);
  for (const box of body.boxes) {
    const { lx, ly, lz, local, axes, half } = box;
    box.x = body.x + m[0] * lx + m[3] * ly + m[6] * lz;
    box.y = body.y + m[1] * lx + m[4] * ly + m[7] * lz;
    box.z = body.z + m[2] * lx + m[5] * ly + m[8] * lz;
    if (local) {
      for (let i = 0; i < 9; i += 3) {
        const x = local[i], y = local[i + 1], z = local[i + 2];
        axes[i] = m[0] * x + m[3] * y + m[6] * z;
        axes[i + 1] = m[1] * x + m[4] * y + m[7] * z;
        axes[i + 2] = m[2] * x + m[5] * y + m[8] * z;
      }
    }
    box.ex = Math.abs(axes[0]) * half[0] + Math.abs(axes[3]) * half[1] + Math.abs(axes[6]) * half[2];
    box.ey = Math.abs(axes[1]) * half[0] + Math.abs(axes[4]) * half[1] + Math.abs(axes[7]) * half[2];
    box.ez = Math.abs(axes[2]) * half[0] + Math.abs(axes[5]) * half[1] + Math.abs(axes[8]) * half[2];
    box.axisAligned = !local && qx === 0 && qy === 0 && qz === 0;
  }
  // Rotate the diagonal inverse inertia into world coordinates.
  if (body.type !== DYNAMIC) return;
  const { ix, iy, iz, inertia } = body;
  for (let row = 0; row < 3; row++) {
    for (let col = row; col < 3; col++) {
      const value = m[row] * m[col] * ix + m[row + 3] * m[col + 3] * iy
        + m[row + 6] * m[col + 6] * iz;
      inertia[3 * row + col] = inertia[3 * col + row] = value;
    }
  }
}

function updateMass(body) {
  if (body.type !== DYNAMIC) return;
  let mass = 0, ix = 0, iy = 0, iz = 0;
  for (const box of body.boxes) {
    if (box.sensor) continue;
    const [x, y, z] = box.half;
    const m = 8 * x * y * z * box.density;
    const { lx, ly, lz, local } = box;
    const a = (y * y + z * z) / 3;
    const b = (x * x + z * z) / 3;
    const c = (x * x + y * y) / 3;
    mass += m;
    ix += m * ((local ? local[0] ** 2 * a + local[3] ** 2 * b + local[6] ** 2 * c : a) + ly * ly + lz * lz);
    iy += m * ((local ? local[1] ** 2 * a + local[4] ** 2 * b + local[7] ** 2 * c : b) + lx * lx + lz * lz);
    iz += m * ((local ? local[2] ** 2 * a + local[5] ** 2 * b + local[8] ** 2 * c : c) + lx * lx + ly * ly);
  }
  body.invMass = mass > 0 ? 1 / mass : 1;
  body.ix = ix > 0 ? 1 / ix : 0;
  body.iy = iy > 0 ? 1 / iy : 0;
  body.iz = iz > 0 ? 1 / iz : 0;
}

function wake(body) {
  if (body.type === DYNAMIC) {
    body.awake = true;
    body.quiet = 0;
  }
}

function sleep(body) {
  const support = body.support;
  if (support) {
    body.supportRevision = support.revision;
    body.supportX = support.x; body.supportY = support.y; body.supportZ = support.z;
    body.supportQx = support.qx; body.supportQy = support.qy;
    body.supportQz = support.qz; body.supportQw = support.qw;
  }
  if (body.boxes.length > 0) updateShapes(body);
  body.awake = false;
  body.vx = body.vy = body.vz = body.wx = body.wy = body.wz = 0;
}

function applyLocks(body) {
  const { mx, my, mz, ax, ay, az } = body;
  body.vx *= mx; body.vy *= my; body.vz *= mz;
  body.wx *= ax; body.wy *= ay; body.wz *= az;
}

function integrate(world, body, dt) {
  if (body.type === DYNAMIC) {
    const gravity = body.gravity * dt;
    const damping = 1 / (1 + body.linearDamping * dt);
    const angularDamping = 1 / (1 + body.angularDamping * dt);
    body.vx = (body.vx + world.gx * gravity) * damping;
    body.vy = (body.vy + world.gy * gravity) * damping;
    body.vz = (body.vz + world.gz * gravity) * damping;
    body.wx *= angularDamping; body.wy *= angularDamping; body.wz *= angularDamping;
    applyLocks(body);
    const speed2 = body.vx ** 2 + body.vy ** 2 + body.vz ** 2;
    if (speed2 > world.maxSpeed ** 2) {
      const scale = world.maxSpeed / Math.sqrt(speed2);
      body.vx *= scale; body.vy *= scale; body.vz *= scale;
    }
  }
  const { vx, vy, vz, wx, wy, wz, qx, qy, qz, qw } = body;
  body.x += vx * dt;
  body.y += vy * dt;
  body.z += vz * dt;
  if (wx !== 0 || wy !== 0 || wz !== 0) {
    const h = 0.5 * dt;
    setRotation(body,
      qx + h * (wx * qw + wy * qz - wz * qy),
      qy + h * (wy * qw + wz * qx - wx * qz),
      qz + h * (wz * qw + wx * qy - wy * qx),
      qw - h * (wx * qx + wy * qy + wz * qz));
  }
  updateShapes(body);
}

// A shape is inserted in every cell overlapped by its AABB. The open-addressed
// table uses separate coordinate keys so even hash collisions cannot hide a pair.
class BoxGrid {
  constructor() {
    this.size = 0;
    this.head = new Int32Array(0);
    this.nodes = new Int32Array(0);
    this.shapes = [];
    this.large = [];
  }

  reset(count) {
    const nodes = 8 * count;
    let size = 32;
    while (size < 2 * nodes) size *= 2;
    if (size > this.size) {
      this.size = size;
      this.head = new Int32Array(size);
      this.x = new Int32Array(size);
      this.y = new Int32Array(size);
      this.z = new Int32Array(size);
    } else {
      this.head.fill(0);
    }
    if (this.nodes.length < 2 * nodes + 2) this.nodes = new Int32Array(2 * nodes + 2);
    this.used = 0;
    this.cells = 0;
    this.shapes.length = 0;
    this.large.length = 0;
  }

  insert(world, box) {
    const index = this.shapes.length;
    box.seen = -1;
    this.shapes.push(box);
    const x0 = Math.floor((box.x - box.ex - CONTACT_SLOP) / CELL_SIZE);
    const y0 = Math.floor((box.y - box.ey - CONTACT_SLOP) / CELL_SIZE);
    const z0 = Math.floor((box.z - box.ez - CONTACT_SLOP) / CELL_SIZE);
    const x1 = Math.floor((box.x + box.ex + CONTACT_SLOP) / CELL_SIZE);
    const y1 = Math.floor((box.y + box.ey + CONTACT_SLOP) / CELL_SIZE);
    const z1 = Math.floor((box.z + box.ez + CONTACT_SLOP) / CELL_SIZE);
    const links = (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1);
    if (links > 27 || this.cells + links > this.size * 0.75
      || Math.max(Math.abs(x0), Math.abs(y0), Math.abs(z0), Math.abs(x1), Math.abs(y1), Math.abs(z1)) > 0x7fffffff) {
      for (let i = 0; i < index; i++) collide(world, box, this.shapes[i]);
      this.large.push(box);
      return;
    }
    for (const other of this.large) collide(world, box, other);
    if (2 * (this.used + links + 1) > this.nodes.length) {
      const nodes = new Int32Array(this.nodes.length * 2);
      nodes.set(this.nodes);
      this.nodes = nodes;
    }
    const mask = this.size - 1;
    const { head, nodes, x, y, z, shapes } = this;
    for (let iz = z0; iz <= z1; iz++) {
      for (let iy = y0; iy <= y1; iy++) {
        const yz = Math.imul(iy, 19349663) ^ Math.imul(iz, 83492791);
        for (let ix = x0; ix <= x1; ix++) {
          const hash = Math.imul(ix, 73856093) ^ yz;
          let slot = (hash ^ (hash >>> 16)) & mask;
          while (head[slot] && (x[slot] !== ix || y[slot] !== iy || z[slot] !== iz)) {
            slot = (slot + 1) & mask;
          }
          if (!head[slot]) {
            x[slot] = ix; y[slot] = iy; z[slot] = iz;
            this.cells++;
          }
          for (let link = head[slot]; link; link = nodes[2 * link + 1]) {
            const other = shapes[nodes[2 * link]];
            if (other.seen === index) continue;
            other.seen = index;
            collide(world, box, other);
          }
          nodes[2 * ++this.used] = index;
          nodes[2 * this.used + 1] = head[slot];
          head[slot] = this.used;
        }
      }
    }
  }
}

function projection(box, x, y, z) {
  const m = box.axes;
  return Math.abs(x * m[0] + y * m[1] + z * m[2]) * box.half[0]
    + Math.abs(x * m[3] + y * m[4] + z * m[5]) * box.half[1]
    + Math.abs(x * m[6] + y * m[7] + z * m[8]) * box.half[2];
}

function testAxis(hit, a, b, x, y, z, edgeBias = 0) {
  const distance = x * hit.dx + y * hit.dy + z * hit.dz;
  const depth = projection(a, x, y, z) + projection(b, x, y, z) - Math.abs(distance);
  if (depth < -CONTACT_SLOP) return false;
  const score = depth + edgeBias;
  if (score < hit.score) {
    const sign = distance < 0 ? -1 : 1;
    hit.score = score;
    hit.depth = depth;
    hit.nx = x * sign; hit.ny = y * sign; hit.nz = z * sign;
  }
  return true;
}

function separatingAxes(hit, a, b) {
  const am = a.axes, bm = b.axes;
  for (let i = 0; i < 9; i += 3) {
    if (!testAxis(hit, a, b, bm[i], bm[i + 1], bm[i + 2])) return false;
    if (!testAxis(hit, a, b, am[i], am[i + 1], am[i + 2])) return false;
  }
  for (let i = 0; i < 9; i += 3) {
    for (let j = 0; j < 9; j += 3) {
      const x = am[i + 1] * bm[j + 2] - am[i + 2] * bm[j + 1];
      const y = am[i + 2] * bm[j] - am[i] * bm[j + 2];
      const z = am[i] * bm[j + 1] - am[i + 1] * bm[j];
      const length2 = x * x + y * y + z * z;
      if (length2 < 1e-6) continue;
      const scale = 1 / Math.sqrt(length2);
      if (!testAxis(hit, a, b, x * scale, y * scale, z * scale, 0.008)) return false;
    }
  }
  return true;
}

function faceAxis(hit, a, b) {
  // A large AABB face that completely covers A along its tangent axes
  // can be resolved as a plane. Edges and rotated geometry use full SAT.
  if (!b.axisAligned) return false;
  const x = Math.abs(hit.dx), y = Math.abs(hit.dy), z = Math.abs(hit.dz);
  if (a.ex < b.ex && x > b.ex * 0.5 && y + a.ey <= b.ey && z + a.ez <= b.ez) {
    hit.nx = hit.dx < 0 ? -1 : 1; hit.ny = hit.nz = 0;
    hit.depth = a.ex + b.ex - x;
  } else if (a.ey <= b.ey * 2 && y > b.ey * 0.5 && x + a.ex <= b.ex && z + a.ez <= b.ez) {
    hit.ny = hit.dy < 0 ? -1 : 1; hit.nx = hit.nz = 0;
    hit.depth = a.ey + b.ey - y;
  } else if (a.ez < b.ez && z > b.ez * 0.5 && x + a.ex <= b.ex && y + a.ey <= b.ey) {
    hit.nz = hit.dz < 0 ? -1 : 1; hit.nx = hit.ny = 0;
    hit.depth = a.ez + b.ez - z;
  } else {
    return false;
  }
  return true;
}

// Work in the other box's local frame and keep the penetrating support
// corners. Averaging coplanar points keeps a flat face from rocking.
function contactCorners(hit, box, other, nx, ny, nz) {
  const m = box.axes, o = other.axes, h = box.half;
  const depth = projection(box, nx, ny, nz);
  const margin = 0.022 + Math.max(0, hit.depth) * 0.25;
  for (let i = 0; i < 8; i++) {
    const x = (i & 1) ? h[0] : -h[0];
    const y = (i & 2) ? h[1] : -h[1];
    const z = (i & 4) ? h[2] : -h[2];
    const rx = m[0] * x + m[3] * y + m[6] * z;
    const ry = m[1] * x + m[4] * y + m[7] * z;
    const rz = m[2] * x + m[5] * y + m[8] * z;
    if (rx * nx + ry * ny + rz * nz < depth - margin) continue;
    const px = box.x + rx, py = box.y + ry, pz = box.z + rz;
    const dx = px - other.x, dy = py - other.y, dz = pz - other.z;
    if (Math.abs(dx * o[0] + dy * o[1] + dz * o[2]) > other.half[0] + margin
      || Math.abs(dx * o[3] + dy * o[4] + dz * o[5]) > other.half[1] + margin
      || Math.abs(dx * o[6] + dy * o[7] + dz * o[8]) > other.half[2] + margin) continue;
    hit.px += px - nx * hit.depth * 0.5;
    hit.py += py - ny * hit.depth * 0.5;
    hit.pz += pz - nz * hit.depth * 0.5;
    hit.points++;
  }
}

function supportPoint(box, x, y, z, hit) {
  hit.px = box.x; hit.py = box.y; hit.pz = box.z;
  for (let i = 0; i < 9; i += 3) {
    const ax = box.axes[i], ay = box.axes[i + 1], az = box.axes[i + 2];
    const dot = ax * x + ay * y + az * z;
    const distance = Math.abs(dot) < 1e-5 ? 0 : Math.sign(dot) * box.half[i / 3];
    hit.px += ax * distance; hit.py += ay * distance; hit.pz += az * distance;
  }
}

function closestPoint(box, x, y, z, result) {
  const m = box.axes;
  const dx = x - box.x, dy = y - box.y, dz = z - box.z;
  const u = clamp(dx * m[0] + dy * m[1] + dz * m[2], -box.half[0], box.half[0]);
  const v = clamp(dx * m[3] + dy * m[4] + dz * m[5], -box.half[1], box.half[1]);
  const w = clamp(dx * m[6] + dy * m[7] + dz * m[8], -box.half[2], box.half[2]);
  result.px = box.x + m[0] * u + m[3] * v + m[6] * w;
  result.py = box.y + m[1] * u + m[4] * v + m[7] * w;
  result.pz = box.z + m[2] * u + m[5] * v + m[8] * w;
}

function effectiveMass(body, x, y, z, rx, ry, rz) {
  const a = (ry * z - rz * y) * body.ax;
  const b = (rz * x - rx * z) * body.ay;
  const c = (rx * y - ry * x) * body.az;
  const m = body.inertia;
  return body.invMass * (x * x * body.mx + y * y * body.my + z * z * body.mz)
    + a * (m[0] * a + m[1] * b + m[2] * c)
    + b * (m[3] * a + m[4] * b + m[5] * c)
    + c * (m[6] * a + m[7] * b + m[8] * c);
}

function impulse(body, x, y, z, rx, ry, rz) {
  const im = body.invMass;
  body.vx += x * im * body.mx;
  body.vy += y * im * body.my;
  body.vz += z * im * body.mz;
  const a = (ry * z - rz * y) * body.ax;
  const b = (rz * x - rx * z) * body.ay;
  const c = (rx * y - ry * x) * body.az;
  const m = body.inertia;
  body.wx += (m[0] * a + m[1] * b + m[2] * c) * body.ax;
  body.wy += (m[3] * a + m[4] * b + m[5] * c) * body.ay;
  body.wz += (m[6] * a + m[7] * b + m[8] * c) * body.az;
}

function relativeVelocity(hit) {
  const { a, b, ax, ay, az, bx, by, bz } = hit;
  hit.vx = a.vx + a.wy * az - a.wz * ay - (b.vx + b.wy * bz - b.wz * by);
  hit.vy = a.vy + a.wz * ax - a.wx * az - (b.vy + b.wz * bx - b.wx * bz);
  hit.vz = a.vz + a.wx * ay - a.wy * ax - (b.vz + b.wx * by - b.wy * bx);
}

function mix(a, b, rule, fallback) {
  switch (rule) {
    case 1: return Math.sqrt(a * b);
    case 2: return Math.min(a, b);
    case 3: return Math.max(a, b);
    case 4: return (a + b) * 0.5;
    case 5: return a * b;
    default: return fallback(a, b);
  }
}

function geometricMean(a, b) {
  return Math.sqrt(a * b);
}

function collide(world, box, other) {
  let a = box.body, b = other.body;
  if (a === b || (!a.awake && !b.awake)) return;
  if (a.type === DYNAMIC && !a.awake && b.type === DYNAMIC) {
    [box, other] = [other, box];
    [a, b] = [b, a];
  }
  const dx = box.x - other.x, dy = box.y - other.y, dz = box.z - other.z;
  if (Math.abs(dx) > box.ex + other.ex + CONTACT_SLOP
    || Math.abs(dy) > box.ey + other.ey + CONTACT_SLOP
    || Math.abs(dz) > box.ez + other.ez + CONTACT_SLOP) return;
  if (box.group && box.group === other.group) {
    if (box.group < 0) return;
  } else if (!box.defaultFilter || !other.defaultFilter) {
    if (!(box.category & other.mask) || !(other.category & box.mask)) return;
  }
  const hit = world.contacts[world.contactCount] ?? {};
  hit.dx = dx; hit.dy = dy; hit.dz = dz;
  hit.score = Infinity;
  if (!(b.type !== DYNAMIC && faceAxis(hit, box, other)) && !separatingAxes(hit, box, other)) return;
  const { nx, ny, nz } = hit;
  hit.px = hit.py = hit.pz = hit.points = 0;
  contactCorners(hit, box, other, -nx, -ny, -nz);
  if (b.type === DYNAMIC || hit.points === 0) contactCorners(hit, other, box, nx, ny, nz);
  if (hit.points) {
    hit.px /= hit.points; hit.py /= hit.points; hit.pz /= hit.points;
  } else {
    // Edge contacts can intersect without either box containing a corner.
    supportPoint(box, -nx, -ny, -nz, hit);
    closestPoint(other, hit.px, hit.py, hit.pz, hit);
  }
  hit.a = a; hit.b = b;
  hit.ax = hit.px - a.x; hit.ay = hit.py - a.y; hit.az = hit.pz - a.z;
  hit.bx = hit.px - b.x; hit.by = hit.py - b.y; hit.bz = hit.pz - b.z;
  relativeVelocity(hit);
  const speed = hit.vx * nx + hit.vy * ny + hit.vz * nz;
  if (speed < -0.26 || hit.depth > 0.045) {
    if (!a.awake) wake(a);
    if (!b.awake) wake(b);
  }
  if (a.awake) recordSupport(world, a, b, nx, ny, nz);
  if (b.awake && b.type === DYNAMIC) recordSupport(world, b, a, -nx, -ny, -nz);
  hit.moveA = a.awake;
  hit.moveB = b.type === DYNAMIC && b.awake;
  hit.weightA = hit.moveA ? a.invMass : 0;
  hit.weightB = hit.moveB ? b.invMass : 0;
  const k = (hit.moveA ? effectiveMass(a, nx, ny, nz, hit.ax, hit.ay, hit.az) : 0)
    + (hit.moveB ? effectiveMass(b, nx, ny, nz, hit.bx, hit.by, hit.bz) : 0);
  if (k === 0) return;
  hit.normalMass = 1 / k;
  hit.bounce = speed < -world.restitutionThreshold
    ? -speed * mix(box.restitution, other.restitution, world.restitutionMixing, Math.max) : 0;
  hit.friction = mix(box.friction, other.friction, world.frictionMixing, geometricMean);
  hit.totalN = hit.totalX = hit.totalY = hit.totalZ = 0;
  world.contacts[world.contactCount++] = hit;
}

function recordSupport(world, a, b, nx, ny, nz) {
  if (nx * world.gx + ny * world.gy + nz * world.gz < -world.gravityLength * 0.45) {
    a.support = b;
  }
}

function supportMoved(body) {
  const support = body.support;
  if (!support) return false;
  return support.revision !== body.supportRevision
    || (support.x - body.supportX) ** 2 + (support.y - body.supportY) ** 2
      + (support.z - body.supportZ) ** 2 > 0.0004
    || Math.abs(support.qx * body.supportQx + support.qy * body.supportQy
      + support.qz * body.supportQz + support.qw * body.supportQw) < 0.9999;
}

function solveVelocity(hit) {
  const { a, b, nx, ny, nz, ax, ay, az, bx, by, bz } = hit;
  relativeVelocity(hit);
  const speed = hit.vx * nx + hit.vy * ny + hit.vz * nz;
  const normal = Math.max(0, hit.totalN + (hit.bounce - speed) * hit.normalMass);
  const change = normal - hit.totalN;
  hit.totalN = normal;
  if (change !== 0) {
    if (hit.moveA) impulse(a, nx * change, ny * change, nz * change, ax, ay, az);
    if (hit.moveB) impulse(b, -nx * change, -ny * change, -nz * change, bx, by, bz);
  }
  if (normal === 0 && hit.totalX === 0 && hit.totalY === 0 && hit.totalZ === 0) return;
  relativeVelocity(hit);
  const n = hit.vx * nx + hit.vy * ny + hit.vz * nz;
  const tx = hit.vx - n * nx, ty = hit.vy - n * ny, tz = hit.vz - n * nz;
  const length = Math.sqrt(tx * tx + ty * ty + tz * tz);
  let x = hit.totalX, y = hit.totalY, z = hit.totalZ;
  if (length > 1e-6) {
    const ux = tx / length, uy = ty / length, uz = tz / length;
    const k = (hit.moveA ? effectiveMass(a, ux, uy, uz, ax, ay, az) : 0)
      + (hit.moveB ? effectiveMass(b, ux, uy, uz, bx, by, bz) : 0);
    if (k > 0) { x -= tx / k; y -= ty / k; z -= tz / k; }
  }
  const limit = hit.friction * normal;
  const size2 = x * x + y * y + z * z;
  if (size2 > limit * limit) {
    const scale = limit / Math.sqrt(size2);
    x *= scale; y *= scale; z *= scale;
  }
  const dx = x - hit.totalX, dy = y - hit.totalY, dz = z - hit.totalZ;
  hit.totalX = x; hit.totalY = y; hit.totalZ = z;
  if (hit.moveA) impulse(a, dx, dy, dz, ax, ay, az);
  if (hit.moveB) impulse(b, -dx, -dy, -dz, bx, by, bz);
}

function projectPosition(hit, limit) {
  const { a, b, nx, ny, nz } = hit;
  const moved = (a.x + hit.ax - b.x - hit.bx) * nx
    + (a.y + hit.ay - b.y - hit.by) * ny + (a.z + hit.az - b.z - hit.bz) * nz;
  const depth = hit.depth - moved - CONTACT_SLOP;
  if (depth <= 0) return;
  const weightA = hit.weightA * (nx * nx * a.mx + ny * ny * a.my + nz * nz * a.mz);
  const weightB = hit.weightB * (nx * nx * b.mx + ny * ny * b.my + nz * nz * b.mz);
  if (weightA + weightB === 0) return;
  const correction = (b.type === DYNAMIC ? Math.min(depth * 0.7, limit) : depth) / (weightA + weightB);
  const da = correction * hit.weightA, db = correction * hit.weightB;
  a.x += nx * da * a.mx; a.y += ny * da * a.my; a.z += nz * da * a.mz;
  b.x -= nx * db * b.mx; b.y -= ny * db * b.my; b.z -= nz * db * b.mz;
}

function stepWorld(world, time, requestedSteps) {
  if (!(time > 0) || !Number.isFinite(time)) return;
  const { moving, fixed, grid, contacts } = world;
  let steps = clamp(Math.trunc(number(Number(requestedSteps), 1)), 1, 16);
  if (world.enableContinuous && steps < 16) {
    for (const body of moving) {
      if (!body.awake || body.type !== DYNAMIC || !Number.isFinite(body.minHalf)) continue;
      const travel = Math.min(world.maxSpeed,
        Math.max(Math.abs(body.vx), Math.abs(body.vy), Math.abs(body.vz))
        + world.gravityLength * Math.abs(body.gravity) * time) * time;
      steps = Math.max(steps, Math.min(16, Math.ceil(travel / body.minHalf)));
    }
  }
  const dt = time / steps;
  for (let sub = 0; sub < steps; sub++) {
    for (const body of moving) {
      if (body.type === KINEMATIC) {
        integrate(world, body, dt);
        continue;
      }
      if (!body.awake && supportMoved(body)) wake(body);
      if (body.awake) {
        body.support = null;
        integrate(world, body, dt);
      }
    }
    grid.reset(world.dynamicShapes.length);
    world.contactCount = 0;
    for (const box of world.dynamicShapes) grid.insert(world, box);
    for (const box of world.dynamicShapes) {
      for (const other of fixed) collide(world, box, other);
    }
    const count = world.contactCount;
    for (let i = 0; i < count; i++) projectPosition(contacts[i], world.contactSpeed * dt);
    for (let pass = 0; pass < 2; pass++) {
      for (let i = 0; i < count; i++) solveVelocity(contacts[i]);
    }
  }
  for (const body of moving) {
    if (body.type !== DYNAMIC || !body.awake) continue;
    if (!world.enableSleep || !body.enableSleep) continue;
    const speed2 = body.vx ** 2 + body.vy ** 2 + body.vz ** 2 + body.wx ** 2 + body.wy ** 2 + body.wz ** 2;
    if ((body.support || world.gravityLength * body.gravity === 0) && speed2 < body.sleepThreshold ** 2) {
      body.quiet += time;
      if (body.quiet >= SLEEP_TIME) sleep(body);
    } else {
      body.quiet = 0;
    }
  }
}

function explode(world, view, ptr) {
  const [x, y, z] = readVector(view, ptr);
  const radius = Math.max(0, number(view.getFloat32(ptr + 12, true)));
  const falloff = Math.max(0, number(view.getFloat32(ptr + 16, true)));
  const pressure = number(view.getFloat32(ptr + 20, true));
  const mask = view.getBigUint64(ptr + 24, true);
  const reach = radius + falloff;
  const point = {};
  for (const body of world.moving) if (body.awake && body.type === DYNAMIC) updateShapes(body);
  for (const box of world.dynamicShapes) {
    if (!(mask & box.category)) continue;
    const dx = box.x - x, dy = box.y - y, dz = box.z - z;
    if (dx * dx + dy * dy + dz * dz > (reach + box.radius) ** 2) continue;
    closestPoint(box, x, y, z, point);
    const distance = Math.sqrt((point.px - x) ** 2 + (point.py - y) ** 2 + (point.pz - z) ** 2);
    if (distance > reach) continue;
    const up = dy + Math.sqrt(dx * dx + dy * dy + dz * dz) * 0.25 + 0.01;
    const scale = Math.sqrt(dx * dx + up * up + dz * dz) || 1;
    const nx = dx / scale, ny = up / scale, nz = dz / scale;
    const [hx, hy, hz] = box.half;
    // The exposed area of a box is the sum of its three projected face areas.
    const m = box.axes;
    const area = 4 * (hy * hz * Math.abs(nx * m[0] + ny * m[1] + nz * m[2])
      + hx * hz * Math.abs(nx * m[3] + ny * m[4] + nz * m[5])
      + hx * hy * Math.abs(nx * m[6] + ny * m[7] + nz * m[8]));
    // Scale the impulse to lift the sample's water-density boxes visibly.
    const strength = pressure * EXPLOSION_IMPULSE_SCALE * box.explosionScale * area
      * (distance <= radius ? 1 : (reach - distance) / falloff);
    const body = box.body;
    wake(body);
    impulse(body, nx * strength, ny * strength, nz * strength,
      point.px - body.x, point.py - body.y, point.pz - body.z);
  }
}

function remove(list, value) {
  const index = list.indexOf(value);
  if (index !== -1) {
    list[index] = list[list.length - 1];
    list.pop();
  }
}

export function createPhysicsImports(mem, options = {}) {
  const worlds = new Map();
  const bodies = new Map();
  let nextWorld = 0;
  let nextHandle = 0n;

  function destroyBody(id) {
    const body = bodies.get(id);
    if (!body) return;
    const world = body.world;
    body.revision++;
    world.bodies.delete(id);
    bodies.delete(id);
    remove(world.moving, body);
    const shapes = body.type === DYNAMIC ? world.dynamicShapes : world.fixed;
    for (const box of body.boxes) remove(shapes, box);
    world.contacts.length = 0;
  }

  function writeVelocity(id, rawPtr, angular) {
    const view = mem.view(), ptr = mem.address(rawPtr), b = bodies.get(id);
    if (angular) writeVector(view, ptr, b?.wx ?? 0, b?.wy ?? 0, b?.wz ?? 0);
    else writeVector(view, ptr, b?.vx ?? 0, b?.vy ?? 0, b?.vz ?? 0);
  }

  function setVelocity(id, rawPtr, angular) {
    const body = bodies.get(id);
    if (!body || body.type === STATIC) return;
    const [x, y, z] = readVector(mem.view(), mem.address(rawPtr));
    if (angular) { body.wx = x; body.wy = y; body.wz = z; }
    else { body.vx = x; body.vy = y; body.vz = z; }
    if (body.type === DYNAMIC) applyLocks(body);
    wake(body);
  }

  // Goose fixed records are packed. The byte offsets below follow the field
  // order in stdlib-web/physics.goose, including the one-byte bool fields.
  const imports = {
    gs_phys_available: () => options.enabled === false ? 0 : 1,
    gs_phys_create_world(rawDef) {
      if (options.enabled === false || worlds.size >= 128 || nextWorld === 0xffffffff) return 0;
      const view = mem.view(), ptr = mem.address(rawDef);
      const [gx, gy, gz] = readVector(view, ptr);
      worlds.set(++nextWorld, {
        gx, gy, gz, gravityLength: Math.sqrt(gx * gx + gy * gy + gz * gz),
        restitutionThreshold: Math.max(0, number(view.getFloat32(ptr + 12, true), 1)),
        contactSpeed: Math.max(0, number(view.getFloat32(ptr + 28, true), 3)),
        maxSpeed: Math.max(0, number(view.getFloat32(ptr + 32, true), 400)),
        enableSleep: Boolean(view.getUint8(ptr + 36)),
        enableContinuous: Boolean(view.getUint8(ptr + 37)),
        frictionMixing: view.getInt32(ptr + 42, true),
        restitutionMixing: view.getInt32(ptr + 46, true),
        bodies: new Map(), moving: [], fixed: [], dynamicShapes: [],
        grid: new BoxGrid(), contacts: [], contactCount: 0,
      });
      return nextWorld;
    },
    gs_phys_destroy_world(id) {
      const world = worlds.get(id >>> 0);
      if (!world) return;
      for (const body of world.bodies.keys()) bodies.delete(body);
      worlds.delete(id >>> 0);
    },
    gs_phys_create_body(id, rawDef) {
      const world = worlds.get(id >>> 0);
      if (!world) return 0n;
      const view = mem.view(), ptr = mem.address(rawDef);
      const type = view.getInt32(ptr, true);
      if (type < STATIC || type > DYNAMIC) return 0n;
      const [x, y, z] = readVector(view, ptr + 4);
      const [vx, vy, vz] = readVector(view, ptr + 32);
      const [wx, wy, wz] = readVector(view, ptr + 44);
      const body = {
        world, type, x, y, z, qx: 0, qy: 0, qz: 0, qw: 1, vx, vy, vz, wx, wy, wz,
        axes: new Array(9).fill(0), inertia: new Array(9).fill(0), boxes: [],
        invMass: type === DYNAMIC ? 1 : 0, ix: 0, iy: 0, iz: 0, minHalf: Infinity,
        linearDamping: Math.max(0, number(view.getFloat32(ptr + 56, true))),
        angularDamping: Math.max(0, number(view.getFloat32(ptr + 60, true))),
        gravity: number(view.getFloat32(ptr + 64, true), 1),
        sleepThreshold: Math.max(0, number(view.getFloat32(ptr + 68, true), 0.05)),
        mx: +!view.getUint8(ptr + 76), my: +!view.getUint8(ptr + 77), mz: +!view.getUint8(ptr + 78),
        ax: +!view.getUint8(ptr + 79), ay: +!view.getUint8(ptr + 80), az: +!view.getUint8(ptr + 81),
        enableSleep: Boolean(view.getUint8(ptr + 82)), awake: type !== STATIC,
        enabled: Boolean(view.getUint8(ptr + 85)), quiet: 0, support: null, supportRevision: 0, revision: 0,
        supportX: 0, supportY: 0, supportZ: 0, supportQx: 0, supportQy: 0, supportQz: 0, supportQw: 1,
      };
      if (type === STATIC || (type === DYNAMIC && !view.getUint8(ptr + 83))) sleep(body);
      if (type === DYNAMIC) applyLocks(body);
      readRotation(view, ptr + 16, body);
      updateShapes(body);
      if (body.enabled && type !== STATIC) world.moving.push(body);
      bodies.set(++nextHandle, body);
      world.bodies.set(nextHandle, body);
      return nextHandle;
    },
    gs_phys_destroy_body: destroyBody,
    gs_phys_create_box_shape(id, rawDef, rawHalf, rawFrame) {
      const body = bodies.get(id);
      if (!body) return 0n;
      const view = mem.view(), ptr = mem.address(rawDef);
      const half = readVector(view, mem.address(rawHalf));
      if (half[0] <= 0 || half[1] <= 0 || half[2] <= 0) return 0n;
      const frame = mem.address(rawFrame);
      const [lx, ly, lz] = readVector(view, frame);
      const rotation = {};
      readRotation(view, frame + 12, rotation);
      const { qx, qy, qz, qw } = rotation;
      let local = null;
      if (qx !== 0 || qy !== 0 || qz !== 0) {
        local = new Array(9).fill(0);
        rotationMatrix(local, qx, qy, qz, qw);
      }
      const category = view.getBigUint64(ptr + 40, true);
      const mask = view.getBigUint64(ptr + 48, true);
      const group = view.getInt32(ptr + 56, true);
      const box = {
        body, half, lx, ly, lz, local, axes: local ? new Array(9).fill(0) : body.axes,
        x: 0, y: 0, z: 0, ex: 0, ey: 0, ez: 0, axisAligned: false, seen: -1,
        radius: Math.sqrt(half[0] ** 2 + half[1] ** 2 + half[2] ** 2),
        friction: Math.max(0, number(view.getFloat32(ptr, true), 0.6)),
        restitution: clamp(number(view.getFloat32(ptr + 4, true)), 0, 1),
        density: Math.max(0, number(view.getFloat32(ptr + 36, true), 1000)),
        category, mask, group, defaultFilter: category === ALL_BITS && mask === ALL_BITS,
        sensor: Boolean(view.getUint8(ptr + 60)),
        explosionScale: number(view.getFloat32(ptr + 67, true), 1),
      };
      body.boxes.push(box);
      if (!box.sensor) body.minHalf = Math.min(body.minHalf, half[0], half[1], half[2]);
      if (view.getUint8(ptr + 65)) updateMass(body);
      updateShapes(body);
      if (body.enabled && !box.sensor) {
        (body.type === DYNAMIC ? body.world.dynamicShapes : body.world.fixed).push(box);
      }
      return ++nextHandle;
    },
    gs_phys_step(id, time, steps) {
      const world = worlds.get(id >>> 0);
      if (world) stepWorld(world, time, steps);
    },
    gs_phys_transform(id, rawPtr) {
      writeTransform(mem.view(), mem.address(rawPtr), bodies.get(id));
    },
    gs_phys_transforms(...args) {
      const input = mem.readSliceArgs(args);
      const output = mem.readSliceArgs(args, input.next);
      const count = Math.min(input.len, output.len);
      if (count <= 0) return;
      const view = mem.view();
      if (!Number.isSafeInteger(count) || input.ptr > view.byteLength - BODY_BYTES * count
        || output.ptr > view.byteLength - TRANSFORM_BYTES * count) {
        throw new RangeError("physics transform slice is outside Wasm memory");
      }
      for (let i = 0, from = input.ptr, to = output.ptr; i < count; i++, from += BODY_BYTES, to += TRANSFORM_BYTES) {
        writeTransform(view, to, bodies.get(view.getBigUint64(from, true)));
      }
    },
    gs_phys_linear_velocity: (id, ptr) => writeVelocity(id, ptr, false),
    gs_phys_angular_velocity: (id, ptr) => writeVelocity(id, ptr, true),
    gs_phys_set_transform(id, rawPos, rawRot) {
      const body = bodies.get(id);
      if (!body) return;
      const view = mem.view();
      [body.x, body.y, body.z] = readVector(view, mem.address(rawPos));
      readRotation(view, mem.address(rawRot), body);
      body.revision++;
      wake(body);
      updateShapes(body);
    },
    gs_phys_set_linear_velocity: (id, ptr) => setVelocity(id, ptr, false),
    gs_phys_set_angular_velocity: (id, ptr) => setVelocity(id, ptr, true),
    gs_phys_set_awake(id, awake) {
      const body = bodies.get(id);
      if (body?.type !== DYNAMIC) return;
      if (awake) wake(body);
      else sleep(body);
    },
    gs_phys_explode(id, rawDef) {
      const world = worlds.get(id >>> 0);
      if (world) explode(world, mem.view(), mem.address(rawDef));
    },
    gs_phys_awake_body_count(id) {
      const world = worlds.get(id >>> 0);
      let count = 0;
      if (world) for (const body of world.moving) if (body.awake) count++;
      return BigInt(count);
    },
    gs_phys_worker_count: (id) => worlds.has(id >>> 0) ? 1n : 0n,
  };

  return {
    imports,
    physics: {
      dispose() {
        bodies.clear();
        worlds.clear();
      },
    },
  };
}
