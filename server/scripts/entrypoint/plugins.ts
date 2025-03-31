import { existsSync, readFileSync } from 'node:fs';
import { green } from 'colorette';
import { envVars, plugins } from 'root/entrypoint/types.ts';
import { installPlugin } from 'root/utils/installPlugin.ts';

const { ARK_DIR } = envVars;

/**
 * Install or update plugins
 */
export const installPlugins = async (): Promise<void> => {
  for (const [plugin, config] of Object.entries(plugins)) {
    const { latestRelease, url, additionalFiles } = config;
    const destination = `${ARK_DIR}/ShooterGame/Binaries/Win64/ArkApi/Plugins/${plugin}`;

    // Check for last installed version
    const lastReleaseFile = `${destination}/last_${plugin}_release.txt`;
    let lastRelease = '';

    if (existsSync(lastReleaseFile)) {
      lastRelease = readFileSync(lastReleaseFile, 'utf8').trim();
    }

    // Compare last installed version with latest release version
    if (lastRelease === latestRelease) {
      console.log(`${plugin} is up to date: ${green(latestRelease)}`);
    } else {
      await installPlugin({ name: plugin, latestRelease, url, destination, additionalFiles });
    }
  }
};
