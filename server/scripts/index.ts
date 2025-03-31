#!/usr/bin/env bun
// Make sure to install dependencies with: bun install

// Import from 'node:' prefix for Node.js built-ins
import { spawn, execSync } from 'node:child_process';
// Third-party dependencies
import { green } from 'colorette';
import { mkdirSync, rmSync, unlinkSync, existsSync, readFileSync } from 'node:fs';
import { installPlugin } from 'root/utils/installPlugin.ts';
import { extractZip } from 'root/utils/extractZip.ts';
import { safeMove } from 'root/utils/safeMove.ts';

// Types
interface PluginConfig {
  latest_release: string;
  url: string;
  additional_files: string[];
}

interface Plugins {
  [key: string]: PluginConfig;
}

// Exit on error equivalent
process.on('uncaughtException', (err: Error) => {
  console.error(err);
  process.exit(1);
});

// Plugin definitions
const plugins: Plugins = {
  ArkShop: {
    latest_release: '1.06',
    url: 'https://cdn.redact.digital/ark/ArkShop',
    additional_files: ['config.json', 'Commented.json'],
  },
  TurretManagerFREE: {
    latest_release: '1.08',
    url: 'http://cdn.redact.digital/ark/TurretManagerFREE',
    additional_files: ['config.json'],
  },
  AdvancedMessagesAscended: {
    latest_release: '1.2',
    url: 'http://cdn.redact.digital/ark/AdvancedMessagesAscended',
    additional_files: ['config.json', 'config_help.json'],
  },
};

// Environment variables
// Try both process.env and Bun.env to ensure we get the values
const ARK_DIR = Bun.env.ARK_DIR || '';
const STEAM_DIR = Bun.env.STEAM_DIR || '';
const ASA_APPID = Bun.env.ASA_APPID || '';
const LOG_FILE = Bun.env.LOG_FILE || '';
const GAME_LOG_FILE = Bun.env.GAME_LOG_FILE || '';
const API_LOG_FILE = Bun.env.API_LOG_FILE || '';
const WINE_LOG_FILE = Bun.env.WINE_LOG_FILE || '';

async function installServerAPI(latestRelease: string): Promise<void> {
  console.log(`Installing latest API ${green(latestRelease)}`);

  const tmpZip = '/tmp/AsaApi.zip';
  const tmpDir = '/tmp/AsaApi';

  // Download
  console.log(`Downloading https://cdn.redact.digital/ark/AsaApi_${latestRelease}.zip to ${tmpZip}...`);
  const response = await fetch(`https://cdn.redact.digital/ark/AsaApi_${latestRelease}.zip`);

  if (!response.ok) {
    throw new Error(`Failed to download AsaApi_${latestRelease}.zip: ${response.status} ${response.statusText}`);
  }

  const zipData = await response.arrayBuffer();
  await Bun.write(tmpZip, zipData);

  // Ensure tmp directory exists
  mkdirSync(tmpDir, { recursive: true });

  // Extract ZIP
  await extractZip(tmpZip, tmpDir);

  // Create directories
  mkdirSync(`${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions`, { recursive: true });

  // Move files
  const moves: [string, string][] = [
    [`${tmpDir}/AsaApiLoader.exe`, `${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe`],
    [`${tmpDir}/AsaApiLoader.pdb`, `${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.pdb`],
    [`${tmpDir}/msdia140.dll`, `${ARK_DIR}/ShooterGame/Binaries/Win64/msdia140.dll`],
    [`${tmpDir}/ArkApi/pdbignores.txt`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/pdbignores.txt`],
    [
      `${tmpDir}/ArkApi/Plugins/Permissions/Permissions.dll`,
      `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/Permissions.dll`,
    ],
    [
      `${tmpDir}/ArkApi/Plugins/Permissions/Permissions.pdb`,
      `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/Permissions.pdb`,
    ],
    [`${tmpDir}/ArkApi/AsaApi.dll`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/AsaApi.dll`],
    [`${tmpDir}/ArkApi/AsaApi.pdb`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/AsaApi.pdb`],
    [
      `${tmpDir}/ArkApi/Plugins/Permissions/PluginInfo.json`,
      `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/PluginInfo.json`,
    ],
  ];

  for (const [src, dest] of moves) {
    if (existsSync(src)) {
      safeMove(src, dest);
    } else {
      console.warn(`Warning: Source file ${src} does not exist, skipping move operation`);
    }
  }

  // Clean up
  unlinkSync(tmpZip);
  rmSync(tmpDir, { recursive: true, force: true });

  // Update version record
  Bun.write(`${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt`, latestRelease);
}

// Main execution function
async function main(): Promise<void> {
  // If command is provided, run it
  if (process.argv.length > 2) {
    const args = process.argv.slice(2);
    execSync(args.join(' '), { stdio: 'inherit' });
    process.exit(0);
  }

  // Install or update ASA server + verify installation
  try {
    console.log(`Running SteamCMD to update ARK server...`);
    console.log(`STEAM_DIR: ${STEAM_DIR}`);
    console.log(`ARK_DIR: ${ARK_DIR}`);
    console.log(`ASA_APPID: ${ASA_APPID}`);

    execSync(`${STEAM_DIR}/steamcmd.sh +force_install_dir ${ARK_DIR} +login anonymous +app_update ${ASA_APPID} +quit`, {
      stdio: 'inherit',
    });
  } catch (error) {
    console.error('Error updating ARK server with SteamCMD:');
    console.error(error);
    console.log('Continuing with the rest of the setup...');
    // Continue execution even if Steam update fails
  }

  // Find latest release of Server API
  const ARK_SERVER_API_LATEST_RELEASE = '1.17';

  // Server API
  if (existsSync(`${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe`)) {
    let lastRelease = '';
    const apiReleasePath = `${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt`;

    if (existsSync(apiReleasePath)) {
      lastRelease = readFileSync(apiReleasePath, 'utf8').trim();
    }

    if (lastRelease === ARK_SERVER_API_LATEST_RELEASE) {
      console.log(`Server API is up to date: ${green(ARK_SERVER_API_LATEST_RELEASE)}`);
    } else {
      await installServerAPI(ARK_SERVER_API_LATEST_RELEASE);
    }
  } else {
    await installServerAPI(ARK_SERVER_API_LATEST_RELEASE);
  }

  // Install plugins
  // for (const [plugin, config] of Object.entries(plugins)) {
  //   const { latest_release, url, additional_files } = config;
  //   const destination = `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/${plugin}`;

  //   // Check for last installed version
  //   const lastReleaseFile = `${destination}/last_${plugin}_release.txt`;
  //   let lastRelease = '';

  //   if (existsSync(lastReleaseFile)) {
  //     lastRelease = readFileSync(lastReleaseFile, 'utf8').trim();
  //   }

  //   // Compare last installed version with latest release version
  //   if (lastRelease === latest_release) {
  //     console.log(`${plugin} is up to date: ${green(latest_release)}`);
  //   } else {
  //     await installPlugin(plugin, latest_release, url, destination, additional_files);
  //   }
  // }

  console.log(
    `${green('------------------------')} Server is ready. Use 'manager' command to manage the server. ${green('------------------------')}`,
  );

  // Start tail logs
  tailLogs();

  // Register SIGTERM handler to stop server gracefully
  process.on('SIGTERM', () => {
    execSync('manager stop --saveworld');
    process.exit(0);
  });

  // Register SIGINT handler to stop server gracefully
  process.on('SIGINT', () => {
    execSync('manager stop --saveworld');
    process.exit(0);
  });
}

// Function to tail multiple log files
function tailLogs(): void {
  const tails: string[] = [];

  setInterval(() => {
    // Check if main log file exists and start tailing
    if (existsSync(LOG_FILE) && !tails.includes(LOG_FILE)) {
      const tailProcess = spawn('tail', ['-F', LOG_FILE]);
      tailProcess.stdout.pipe(process.stdout);
      tailProcess.stderr.pipe(process.stderr);
      tails.push(LOG_FILE);
    }

    // Check other log patterns
    for (const logPattern of [GAME_LOG_FILE, API_LOG_FILE, WINE_LOG_FILE]) {
      try {
        // Use ls to find latest log for pattern
        const latestLog = execSync(`ls -t ${logPattern} 2>/dev/null | head -n 1`, { encoding: 'utf8' }).trim();

        if (latestLog && !tails.includes(latestLog)) {
          const tailProcess = spawn('tail', ['-F', latestLog]);
          tailProcess.stdout.pipe(process.stdout);
          tailProcess.stderr.pipe(process.stderr);
          tails.push(latestLog);
        }
      } catch (error) {
        // Ignore errors from ls command
      }
    }
  }, 5000);
}

// Run the main function
main().catch((err: Error) => {
  console.error(err);
  process.exit(1);
});
