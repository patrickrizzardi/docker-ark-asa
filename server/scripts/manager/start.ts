#!/usr/bin/env ts-node

/**
 * Server start script for ASA
 * Combined functionality from manager_server_start.sh and manager_server_api_start.sh
 */

import type { ChildProcess } from 'child_process';
import { execSync, spawn } from 'child_process';
import * as fs from 'fs';

// Define custom process environment for type safety
type ProcessEnv = Record<string, string | undefined>;

// Process environment variables
const {
  SERVER_MAP,
  SESSION_NAME,
  SERVER_PORT,
  MAX_PLAYERS,
  SERVER_PASSWORD,
  ARK_ADMIN_PASSWORD,
  RCON_PORT,
  QUERY_PORT,
  ARK_EXTRA_OPTS,
  MODS,
  BATTLEYE,
  CLUSTER,
  EVENT,
  ARK_EXTRA_DASH_OPTS,
  STEAM_COMPAT_DATA_PATH,
  ARK_DIR,
  WINE_LOG_FILE,
} = process.env;

// Build command string with options
const buildCommandString = (): string => {
  let cmd = `${SERVER_MAP}?listen?SessionName="${SESSION_NAME}"?Port=${SERVER_PORT}`;

  if (MAX_PLAYERS) {
    cmd += `?MaxPlayers=${MAX_PLAYERS}`;
  }

  if (SERVER_PASSWORD) {
    cmd += `?ServerPassword=${SERVER_PASSWORD}`;
  }

  if (ARK_ADMIN_PASSWORD) {
    cmd += `?ServerAdminPassword="${ARK_ADMIN_PASSWORD}"`;
  }

  if (RCON_PORT) {
    cmd += `?RCONEnabled=True?RCONPort=${RCON_PORT}`;
  }

  if (QUERY_PORT) {
    cmd += `?QueryPort=${QUERY_PORT}`;
  }

  cmd += ARK_EXTRA_OPTS ?? '';

  return cmd;
};

// Build server flags
const buildServerFlags = (): string => {
  let arkFlags = '';

  // Install mods
  if (MODS) {
    arkFlags += ` -mods=${MODS}`;
  }

  arkFlags += ' -log -ServerRCONOutputTribeLogs -gameplaylogging -servergamelog -servergamelogincludetribelogs';

  // BattlEye settings
  if (BATTLEYE === 'True' || BATTLEYE === '1' || BATTLEYE === 'true') {
    arkFlags += ' -UseBattlEye';
  } else {
    arkFlags += ' -NoBattlEye';
  }

  if (MAX_PLAYERS) {
    arkFlags += ` -WinLiveMaxPlayers=${MAX_PLAYERS}`;
  }

  if (CLUSTER) {
    arkFlags += ` -clusterid=${CLUSTER}`;
  }

  if (EVENT) {
    arkFlags += ` -ActiveEvent=${EVENT}`;
  } else {
    arkFlags += ' -ActiveEvent=None';
  }

  arkFlags += ARK_EXTRA_DASH_OPTS ? ` ${ARK_EXTRA_DASH_OPTS}` : '';

  return arkFlags;
};

// Safely process environment variable that might contain quotes
const processSteamPath = (path: string | undefined): string => {
  if (!path) return '';

  // Replace environment variables like $HOME with their values
  return path.replace(/\$(?:[A-Za-z0-9_]+)/g, (match) => {
    const varName = match.substring(1); // Remove the $ prefix
    return process.env[varName] ?? '';
  });
};

// Handle segmentation fault errors
const handleSegmentationFault = (): void => {
  console.error('\x1b[31m%s\x1b[0m', 'FATAL ERROR: Wine process crashed with segmentation fault');
  console.error('\x1b[33m%s\x1b[0m', 'This is often caused by memory issues or Wine compatibility problems');
  console.error('\x1b[36m%s\x1b[0m', 'Troubleshooting tips:');
  console.error('1. Check system memory and disk space');
  console.error('2. Verify the installed Wine version is compatible with ASA');
  console.error('3. Try adjusting server parameters or removing some flags');
  if (WINE_LOG_FILE) {
    console.error('4. Check the full logs at:', WINE_LOG_FILE);
  }
};

// Handle null exit code (unexpected termination)
const handleNullExitCode = (): void => {
  console.error('\x1b[31m%s\x1b[0m', 'Server process was terminated unexpectedly (exit code null)');
  console.error('\x1b[33m%s\x1b[0m', 'This usually indicates:');
  console.error('1. Wine process crashed immediately or failed to start');
  console.error('2. Process was killed by the system (possibly OOM killer)');
  console.error('3. Insufficient memory allocation for the container');
  console.error('\x1b[36m%s\x1b[0m', 'Recommended actions:');
  console.error('1. Check Docker container logs: docker logs <container-id>');
  console.error('2. Increase memory allocation for the container');
  console.error('3. Try running with fewer parameters or without certain flags');
  console.error('4. Check if any Wine prerequisites are missing');
};

// Process stderr output
const processStderrOutput = (data: Buffer): void => {
  const output = data.toString();

  // Check for common errors
  if (output.includes('Segmentation fault') || output.includes('core dumped')) {
    handleSegmentationFault();
  }
};

// Set up output logging
const setupOutputLogging = (serverProcess: ChildProcess): void => {
  if (!WINE_LOG_FILE || !serverProcess.stdout || !serverProcess.stderr) return;

  const logStream = fs.createWriteStream(WINE_LOG_FILE, { flags: 'a' });

  serverProcess.stdout.on('data', (data) => logStream.write(data));
  serverProcess.stderr.on('data', (data) => {
    logStream.write(data);
    processStderrOutput(data);
  });
};

// Set up error handling
const setupErrorHandling = (serverProcess: ChildProcess): void => {
  if (serverProcess.stderr && !WINE_LOG_FILE) {
    // If no log file, at least process stderr for error detection
    serverProcess.stderr.on('data', processStderrOutput);
  }

  serverProcess.on('error', (err) => {
    console.error('\x1b[31m%s\x1b[0m', `Failed to start server process: ${err.message}`);
  });

  serverProcess.on('close', (code: number | null) => {
    if (code === 0) {
      console.log(`Server process exited with code ${code}`);
      return;
    }

    if (code === null) {
      handleNullExitCode();
      return;
    }

    console.error('\x1b[31m%s\x1b[0m', `Server process exited with error code ${code}`);

    if (code === 139) {
      console.error('\x1b[31m%s\x1b[0m', 'Exit code 139 indicates a segmentation fault');
      console.error('\x1b[33m%s\x1b[0m', 'This is likely a memory-related issue with Wine');
    }
  });
};

// Check system resources
const checkSystemResources = (): void => {
  console.log('\nChecking system resources before starting server...');
  try {
    const memInfo = execSync('free -m').toString();
    console.log(memInfo);

    // Also check CPU info
    const cpuInfo = execSync('nproc').toString().trim();
    console.log(`Available CPU cores: ${cpuInfo}`);
  } catch (err) {
    console.log('Unable to check system resources:', err instanceof Error ? err.message : String(err));
  }
};

// Set up logging for the server process
const setupLogging = (serverProcess: ChildProcess): void => {
  setupOutputLogging(serverProcess);
  setupErrorHandling(serverProcess);
};

// Main function to start the server
const startServer = (exeFile = 'ArkAscendedServer.exe'): void => {
  const cmd = buildCommandString();
  const arkFlags = buildServerFlags();

  // Fix for docker compose exec parsing inconsistencies
  const steamDataPath = processSteamPath(STEAM_COMPAT_DATA_PATH);

  // Starting server
  const fullCommand = `wine "${ARK_DIR}/ShooterGame/Binaries/Win64/${exeFile}" ${cmd} ${arkFlags}`;

  console.log(`Starting server with command: ${fullCommand}`);

  // Create type-safe environment object
  const serverEnv: ProcessEnv = {};

  // Copy all existing environment variables
  for (const key in process.env) {
    if (Object.prototype.hasOwnProperty.call(process.env, key)) {
      serverEnv[key] = process.env[key];
    }
  }

  // Add our custom variable
  serverEnv.STEAM_COMPAT_DATA_PATH = steamDataPath;

  try {
    // Check system resources before starting
    checkSystemResources();

    console.log('\nStarting ARK server process...');
    const serverProcess = spawn('wine', [`${ARK_DIR}/ShooterGame/Binaries/Win64/${exeFile}`, cmd, ...arkFlags.split(' ').filter((arg) => arg !== '')], {
      stdio: WINE_LOG_FILE ? ['ignore', 'pipe', 'pipe'] : 'inherit',
      env: serverEnv,
    });

    setupLogging(serverProcess);

    // Set up restart on crash (optional)
    /*
    serverProcess.on('close', (code) => {
      if ((code !== 0 && code !== null) || code === null) {
        console.log(`Server crashed with code ${code}, restarting in 10 seconds...`);
        setTimeout(() => startServer(exeFile), 10000);
      }
    });
    */
  } catch (error) {
    console.error('\x1b[31m%s\x1b[0m', `Failed to start server: ${error instanceof Error ? error.message : String(error)}`);
  }
};

// Parse command line arguments
const args = process.argv.slice(2);
const exeFile = args[0] ?? 'ArkAscendedServer.exe';

// Start the server
startServer(exeFile);
