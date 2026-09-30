const net = require("net");

const portArg = process.argv.find((arg) => /^\d+$/.test(arg));
const port = Number(process.env.SEBI_POKELINK_PORT || portArg || 54545);
const markerTtlMs = Math.max(100, Number(process.env.SEBI_MARKER_TTL_MS || 60000));
let nextId = 1;
const clients = new Map();

function now() {
  return new Date().toISOString().replace("T", " ").replace(/\..+$/, "");
}

function log(message) {
  console.log(`[${now()}] ${message}`);
}

function send(client, line) {
  if (!client.socket.destroyed) {
    client.socket.write(`${line}\n`);
  }
}

function broadcast(sender, line) {
  for (const client of clients.values()) {
    if (client !== sender) send(client, line);
  }
}

function broadcastAll(line) {
  for (const client of clients.values()) {
    send(client, line);
  }
}

function safeField(value) {
  return String(value || "").replace(/[\r\n]/g, "");
}

const server = net.createServer((socket) => {
  socket.setNoDelay(true);
  socket.setKeepAlive(true, 15000);

  const client = {
    id: String(nextId++),
    name: "Player",
    socket,
    buffer: "",
    lastPlayerLine: null,
    lastMarkerLine: null,
    markerTimeout: null,
  };
  clients.set(client.id, client);
  send(client, `WELCOME|${client.id}`);
  log(`client ${client.id} connected from ${socket.remoteAddress}`);

  socket.on("data", (chunk) => {
    client.buffer += chunk.toString("utf8");
      if (client.buffer.length > 16 * 1024 * 1024) client.buffer = client.buffer.slice(-8 * 1024 * 1024);

    let newline;
    while ((newline = client.buffer.indexOf("\n")) >= 0) {
      const raw = client.buffer.slice(0, newline).replace(/\r$/, "");
      client.buffer = client.buffer.slice(newline + 1);
      if (!raw) continue;

      const parts = raw.split("|");
      const type = parts[0];
      if (type === "HELLO") {
        client.name = safeField(parts[1] || client.name);
        log(`client ${client.id} is ${client.name}`);
        for (const other of clients.values()) {
          if (other !== client && other.lastPlayerLine) send(client, other.lastPlayerLine);
          if (other !== client && other.lastMarkerLine) send(client, other.lastMarkerLine);
        }
      } else if (type === "POS") {
        const payload = parts.slice(1).map(safeField).join("|");
        client.lastPlayerLine = `PLAYER|${client.id}|${payload}`;
        broadcast(client, client.lastPlayerLine);
      } else if (type === "MARK") {
        const payload = parts.slice(1).map(safeField).join("|");
        client.lastMarkerLine = `MARKER|${client.id}|${payload}`;
        broadcastAll(client.lastMarkerLine);
        if (client.markerTimeout) clearTimeout(client.markerTimeout);
        const markerLine = client.lastMarkerLine;
        client.markerTimeout = setTimeout(() => {
          client.markerTimeout = null;
          if (client.lastMarkerLine !== markerLine) return;
          client.lastMarkerLine = null;
          broadcastAll(`MARKER_CLEAR|${client.id}`);
        }, markerTtlMs);
      } else if (type === "CLEAR_MARK") {
        if (client.markerTimeout) clearTimeout(client.markerTimeout);
        client.markerTimeout = null;
        client.lastMarkerLine = null;
        broadcastAll(`MARKER_CLEAR|${client.id}`);
      } else if (type === "DIRECT") {
        const targetId = parts[1];
        const target = clients.get(targetId);
        if (target) {
          const payload = parts.slice(2).map(safeField).join("|");
          send(target, `DIRECT|${client.id}|${payload}`);
        } else {
          send(client, `DIRECT_FAIL|${safeField(targetId)}`);
        }
      } else if (type === "PING") {
        send(client, `PONG|${Date.now()}`);
      }
    }
  });

  function close() {
    if (!clients.has(client.id)) return;
    clients.delete(client.id);
    if (client.markerTimeout) clearTimeout(client.markerTimeout);
    client.markerTimeout = null;
    if (client.lastMarkerLine) broadcast(client, `MARKER_CLEAR|${client.id}`);
    broadcast(client, `LEAVE|${client.id}`);
    log(`client ${client.id} disconnected`);
  }

  socket.on("close", close);
  socket.on("error", (error) => {
    log(`client ${client.id} error: ${error.message}`);
    close();
  });
});

const bindHost = process.env.SEBI_MULTIPLAYER_BIND_HOST || "0.0.0.0";

server.listen(port, bindHost, () => {
  log(`SebiPokeLink visual multiplayer relay listening on ${bindHost}:${port}`);
});

process.on("SIGINT", () => {
  log("shutting down");
  server.close(() => process.exit(0));
});
