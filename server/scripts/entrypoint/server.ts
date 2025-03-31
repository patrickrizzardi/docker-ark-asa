import { execSync } from 'node:child_process';
import { envVars } from 'root/entrypoint/types.ts';

const { ARK_DIR, ASA_APPID, STEAM_DIR } = envVars;

/**
 * Update the ARK server using SteamCMD
 */
export const updateArkServer = (): void => {
  try {
    console.log(`Running SteamCMD to update ARK server...`);

    execSync(`${STEAM_DIR}/steamcmd.sh +force_install_dir ${ARK_DIR} +login anonymous +app_update ${ASA_APPID} +quit`, {
      stdio: 'inherit',
    });
  } catch (error) {
    console.error('Error updating ARK server with SteamCMD:');
    console.error(error);
    console.log('Continuing with the rest of the setup...');
    // Continue execution even if Steam update fails
  }
};

/**
 * Setup graceful shutdown handlers
 */
export const setupShutdownHandlers = (): void => {
  // Register SIGTERM handler to stop server gracefully
  process.on('SIGTERM', () => {
    console.log('Received SIGTERM signal. Stopping server...');
    execSync('manager stop --saveworld');
    process.exit(0);
  });

  // Register SIGINT handler to stop server gracefully
  process.on('SIGINT', () => {
    console.log('Received SIGINT signal. Stopping server...');
    execSync('manager stop --saveworld');
    process.exit(0);
  });
};
