import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { green } from 'colorette';
import { ARK_SERVER_API_LATEST_RELEASE, CDN_URL, envVars } from 'root/entrypoint/types.ts';
import { extractZip } from 'root/utils/extractZip.ts';
import { safeMove } from 'root/utils/safeMove.ts';

const { ARK_DIR } = envVars;

/**
 * Downloads and installs the Server API
 */
export const installServerApi = async (latestRelease: string): Promise<void> => {
  console.log(`Installing latest API ${green(latestRelease)}`);

  const tmpZip = '/tmp/AsaApi.zip';
  const tmpDir = '/tmp/AsaApi';

  try {
    // Download
    console.log(`Downloading ${CDN_URL}/AsaApi_${latestRelease}.zip to ${tmpZip}...`);
    const response = await fetch(`${CDN_URL}/AsaApi_${latestRelease}.zip`);

    if (!response.ok) {
      throw new Error(`Failed to download AsaApi_${latestRelease}.zip: ${response.status} ${response.statusText}`);
    }

    const zipData = await response.arrayBuffer();
    await Bun.write(tmpZip, zipData);

    // Ensure tmp directory exists
    mkdirSync(tmpDir, { recursive: true });

    // Extract ZIP
    extractZip(tmpZip, tmpDir);

    // Create directories
    mkdirSync(`${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions`, { recursive: true });

    // Move files
    moveApiFiles(tmpDir);

    // Update version record
    await Bun.write(`${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt`, latestRelease);
  } catch (error) {
    console.error(`Error installing Server API: ${error instanceof Error ? error.message : 'Unknown error'}`);
    throw error;
  }
};

/**
 * Moves API files from temporary directory to their final destination
 */
export const moveApiFiles = (tmpDir: string): void => {
  const moves: Array<[string, string]> = [
    [`${tmpDir}/AsaApiLoader.exe`, `${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe`],
    [`${tmpDir}/AsaApiLoader.pdb`, `${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.pdb`],
    [`${tmpDir}/msdia140.dll`, `${ARK_DIR}/ShooterGame/Binaries/Win64/msdia140.dll`],
    [`${tmpDir}/ArkApi/pdbignores.txt`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/pdbignores.txt`],
    [`${tmpDir}/ArkApi/Plugins/Permissions/Permissions.dll`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/Permissions.dll`],
    [`${tmpDir}/ArkApi/Plugins/Permissions/Permissions.pdb`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/Permissions.pdb`],
    [`${tmpDir}/ArkApi/AsaApi.dll`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/AsaApi.dll`],
    [`${tmpDir}/ArkApi/AsaApi.pdb`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/AsaApi.pdb`],
    [`${tmpDir}/ArkApi/Plugins/Permissions/PluginInfo.json`, `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/Permissions/PluginInfo.json`],
  ];

  for (const [src, dest] of moves) {
    if (existsSync(src)) {
      safeMove(src, dest);
    } else {
      console.warn(`Warning: Source file ${src} does not exist, skipping move operation`);
    }
  }
};

/**
 * Check and update the Server API if needed
 */
export const checkAndUpdateServerApi = async (): Promise<void> => {
  if (existsSync(`${ARK_DIR}/ShooterGame/Binaries/Win64/AsaApiLoader.exe`)) {
    let lastRelease = '';
    const apiReleasePath = `${ARK_DIR}/ShooterGame/Binaries/last_server_api_release.txt`;

    if (existsSync(apiReleasePath)) {
      lastRelease = readFileSync(apiReleasePath, 'utf8').trim();
    }

    if (lastRelease === ARK_SERVER_API_LATEST_RELEASE) {
      console.log(`Server API is up to date: ${green(ARK_SERVER_API_LATEST_RELEASE)}`);
    } else {
      await installServerApi(ARK_SERVER_API_LATEST_RELEASE);
    }
  } else {
    await installServerApi(ARK_SERVER_API_LATEST_RELEASE);
  }
};
