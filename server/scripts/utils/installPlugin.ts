import { mkdirSync, rmSync, unlinkSync } from 'node:fs';
import { green } from 'colorette';
import { safeMove } from 'utils/safeMove.ts';
import { extractZip } from 'utils/extractZip.ts';

// Function to download and install plugins
export const installPlugin = async ({
  name,
  latestRelease,
  url,
  destination,
  additionalFiles,
}: {
  name: string;
  latestRelease: string;
  url: string;
  destination: string;
  additionalFiles: Array<string>;
}): Promise<void> => {
  console.log(`Installing latest ${name} ${green(latestRelease)}`);

  const tmpZip = `/tmp/${name}.zip`;
  const tmpDir = `/tmp/${name}`;

  // Download
  console.log(`Downloading ${url}/${name}_${latestRelease}.zip to ${tmpZip}...`);
  const response = await fetch(`${url}/${name}_${latestRelease}.zip`);

  if (!response.ok) {
    throw new Error(`Failed to download ${url}/${name}_${latestRelease}.zip: ${response.status} ${response.statusText}`);
  }

  const zipData = await response.arrayBuffer();
  await Bun.write(tmpZip, zipData);

  // Ensure tmp directory exists
  mkdirSync(tmpDir, { recursive: true });

  // Extract ZIP
  extractZip(tmpZip, tmpDir);

  // Create destination directory
  mkdirSync(destination, { recursive: true });

  moveFiles({ tmpDir, destination, name, files: additionalFiles });

  cleanUpTmpFiles({ tmpDir, tmpZip });

  // Update version record
  await Bun.write(`${destination}/last_${name}_release.txt`, latestRelease);
};

const moveFiles = ({ tmpDir, destination, name, files }: { tmpDir: string; destination: string; name: string; files: Array<string> }): void => {
  // Move default files
  safeMove(`${tmpDir}/${name}.dll`, `${destination}/${name}.dll`);
  safeMove(`${tmpDir}/${name}.pdb`, `${destination}/${name}.pdb`);
  safeMove(`${tmpDir}/PluginInfo.json`, `${destination}/PluginInfo.json`);

  // Move additional files if specified
  for (const file of files) {
    safeMove(`${tmpDir}/${file}`, `${destination}/${file}`);
  }
};

const cleanUpTmpFiles = ({ tmpDir, tmpZip }: { tmpDir: string; tmpZip: string }): void => {
  unlinkSync(tmpZip);
  rmSync(tmpDir, { recursive: true, force: true });
};
