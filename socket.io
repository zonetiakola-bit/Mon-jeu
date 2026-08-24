const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

app.use(express.static(path.join(__dirname, 'public')));

const players = {};
const bullets = [];

const SPEED = 5;
const BULLET_SPEED = 10;
const CANVAS_WIDTH = 800;
const CANVAS_HEIGHT = 500;

const walls = [
  { x: 150, y: 100, width: 200, height: 30 },
  { x: 450, y: 200, width: 30, height: 200 },
  { x: 200, y: 350, width: 300, height: 30 }
];

function checkCollision(rect1, rect2) {
  return (
    rect1.x < rect2.x + rect2.width &&
    rect1.x + rect1.size > rect2.x &&
    rect1.y < rect2.y + rect2.height &&
    rect1.y + rect1.size > rect2.y
  );
}

function pointInRect(px, py, rect) {
  return (
    px >= rect.x &&
    px <= rect.x + rect.width &&
    py >= rect.y &&
    py <= rect.y + rect.height
  );
}

function getRandomColor() {
  const letters = '0123456789ABCDEF';
  let color = '#';
  for (let i = 0; i < 6; i++) color += letters[Math.floor(Math.random() * 16)];
  return color;
}

io.on('connection', (socket) => {
  socket.emit('mapInit', { walls, canvasWidth: CANVAS_WIDTH, canvasHeight: CANVAS_HEIGHT });

  socket.on('initPlayer', (data) => {
    const cleanName = (data.name || 'Anonyme').substring(0, 12);
    players[socket.id] = {
      x: 50,
      y: 50,
      size: 30,
      hp: 100,
      maxHp: 100,
      kills: 0,
      name: cleanName,
      color: getRandomColor(),
      inputs: { up: false, down: false, left: false, right: false }
    };
  });

  socket.on('playerInput', (inputs) => {
    if (players[socket.id]) players[socket.id].inputs = inputs;
  });

  socket.on('shoot', (target) => {
    const p = players[socket.id];
    if (!p) return;

    const centerX = p.x + p.size / 2;
    const centerY = p.y + p.size / 2;
    const angle = Math.atan2(target.y - centerY, target.x - centerX);

    bullets.push({
      id: Math.random().toString(),
      ownerId: socket.id,
      x: centerX,
      y: centerY,
      radius: 5,
      vx: Math.cos(angle) * BULLET_SPEED,
      vy: Math.sin(angle) * BULLET_SPEED
    });
  });

  socket.on('disconnect', () => {
    delete players[socket.id];
  });
});

setInterval(() => {
  for (const id in players) {
    const p = players[id];

    let targetX = p.x;
    if (p.inputs.left) targetX -= SPEED;
    if (p.inputs.right) targetX += SPEED;
    targetX = Math.max(0, Math.min(CANVAS_WIDTH - p.size, targetX));

    let canMoveX = true;
    for (const wall of walls) {
      if (checkCollision({ x: targetX, y: p.y, size: p.size }, wall)) {
        canMoveX = false;
        break;
      }
    }
    if (canMoveX) p.x = targetX;

    let targetY = p.y;
    if (p.inputs.up) targetY -= SPEED;
    if (p.inputs.down) targetY += SPEED;
    targetY = Math.max(0, Math.min(CANVAS_HEIGHT - p.size, targetY));

    let canMoveY = true;
    for (const wall of walls) {
      if (checkCollision({ x: p.x, y: targetY, size: p.size }, wall)) {
        canMoveY = false;
        break;
      }
    }
    if (canMoveY) p.y = targetY;
  }

  for (let i = bullets.length - 1; i >= 0; i--) {
    const b = bullets[i];
    b.x += b.vx;
    b.y += b.vy;

    let destroyed = false;

    if (b.x < 0 || b.x > CANVAS_WIDTH || b.y < 0 || b.y > CANVAS_HEIGHT) {
      destroyed = true;
    }

    if (!destroyed) {
      for (const wall of walls) {
        if (pointInRect(b.x, b.y, wall)) {
          destroyed = true;
          break;
        }
      }
    }

    if (!destroyed) {
      for (const id in players) {
        if (id !== b.ownerId) {
          const p = players[id];
          if (pointInRect(b.x, b.y, { x: p.x, y: p.y, width: p.size, height: p.size })) {
            destroyed = true;
            p.hp -= 20;

            if (p.hp <= 0) {
              p.hp = p.maxHp;
              p.x = 50;
              p.y = 50;
              if (players[b.ownerId]) {
                players[b.ownerId].kills += 1;
              }
            }
            break;
          }
        }
      }
    }

    if (destroyed) {
      bullets.splice(i, 1);
    }
  }

  io.emit('gameState', { players, bullets });
}, 1000 / 60);

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Serveur démarré sur le port ${PORT}`));
