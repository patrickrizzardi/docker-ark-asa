import { green } from 'colorette';
import { mkdirSync, rmSync, unlinkSync } from 'node:fs';
import { safeMove } from 'utils/safeMove.ts';
import { extractZip } from 'utils/extractZip.ts';

// Function to download and install plugins
export async function installPlugin(
  name: string,
  latestRelease: string,
  url: string,
  destination: string,
  additionalFiles: string[],
): Promise<void> {
  console.log(`Installing latest ${name} ${green(latestRelease)}`);

  const tmpZip = `/tmp/${name}.zip`;
  const tmpDir = `/tmp/${name}`;

  // Download
  console.log(`Downloading ${url}/${name}_${latestRelease}.zip to ${tmpZip}...`);
  const response = await fetch(`${url}/${name}_${latestRelease}.zip`);

  if (!response.ok) {
    throw new Error(
      `Failed to download ${url}/${name}_${latestRelease}.zip: ${response.status} ${response.statusText}`,
    );
  }

  const zipData = await response.arrayBuffer();
  await Bun.write(tmpZip, zipData);

  // Ensure tmp directory exists
  mkdirSync(tmpDir, { recursive: true });

  // Extract ZIP
  await extractZip(tmpZip, tmpDir);

  // Create destination directory
  mkdirSync(destination, { recursive: true });

  // Move default files
  safeMove(`${tmpDir}/${name}.dll`, `${destination}/${name}.dll`);
  safeMove(`${tmpDir}/${name}.pdb`, `${destination}/${name}.pdb`);
  safeMove(`${tmpDir}/PluginInfo.json`, `${destination}/PluginInfo.json`);

  // Move additional files if specified
  for (const file of additionalFiles) {
    safeMove(`${tmpDir}/${file}`, `${destination}/${file}`);
  }

  // Clean up
  unlinkSync(tmpZip);
  rmSync(tmpDir, { recursive: true, force: true });

  // Update version record
  Bun.write(`${destination}/last_${name}_release.txt`, latestRelease);
}
