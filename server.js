const http = require("node:http");
const { spawn } = require("node:child_process");
const { existsSync, writeFileSync, rmSync } = require("node:fs");
const path = require("node:path");

const root = __dirname;
const publicHost = process.env.SPEECH_HOST || "0.0.0.0";
const publicPort = Number(process.env.SPEECH_PORT || "8000");
const backendHost = "127.0.0.1";
const backendPort = Number(process.env.SPEECH_BACKEND_PORT || "8765");
const pythonExe = path.join(root, ".venv", "Scripts", "python.exe");
const backendPidFile = path.join(root, "server.backend.pid");

if (!existsSync(pythonExe)) {
  console.error("No se encontro Python en .venv. Ejecuta primero: scripts\\install.bat");
  process.exit(1);
}

const backend = spawn(
  pythonExe,
  ["-m", "uvicorn", "app.main:app", "--host", backendHost, "--port", String(backendPort)],
  {
    cwd: root,
    stdio: ["ignore", "inherit", "inherit"],
    windowsHide: true,
  },
);

writeFileSync(backendPidFile, String(backend.pid));

let shuttingDown = false;

backend.on("exit", (code, signal) => {
  try {
    rmSync(backendPidFile, { force: true });
  } catch {
    // Nothing useful to do during shutdown.
  }

  if (!shuttingDown) {
    console.error(`El backend Python termino inesperadamente. code=${code} signal=${signal}`);
    process.exit(1);
  }
});

function shutdown() {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;
  server.close(() => {
    try {
      backend.kill();
    } catch {
      // The process may already be gone.
    }
  });

  setTimeout(() => process.exit(0), 3000).unref();
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

function proxyRequest(clientReq, clientRes) {
  const headers = { ...clientReq.headers };
  headers.host = `${backendHost}:${backendPort}`;

  const backendReq = http.request(
    {
      hostname: backendHost,
      port: backendPort,
      method: clientReq.method,
      path: clientReq.url,
      headers,
    },
    (backendRes) => {
      const responseHeaders = { ...backendRes.headers };
      delete responseHeaders.connection;
      delete responseHeaders["keep-alive"];
      delete responseHeaders["proxy-authenticate"];
      delete responseHeaders["proxy-authorization"];
      delete responseHeaders.te;
      delete responseHeaders.trailer;
      delete responseHeaders["transfer-encoding"];
      delete responseHeaders.upgrade;

      clientRes.writeHead(backendRes.statusCode || 502, responseHeaders);
      backendRes.pipe(clientRes);
    },
  );

  backendReq.on("error", (error) => {
    if (!clientRes.headersSent) {
      clientRes.writeHead(502, { "content-type": "application/json" });
    }
    clientRes.end(JSON.stringify({ detail: `Backend Python no disponible: ${error.message}` }));
  });

  clientReq.pipe(backendReq);
}

const server = http.createServer(proxyRequest);

server.on("clientError", (_error, socket) => {
  socket.end("HTTP/1.1 400 Bad Request\r\n\r\n");
});

server.listen(publicPort, publicHost, () => {
  console.log(`Node proxy escuchando en http://${publicHost}:${publicPort}`);
  console.log(`Backend Python escuchando en http://${backendHost}:${backendPort}`);
});
