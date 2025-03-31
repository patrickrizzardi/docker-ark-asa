import { execSync } from 'node:child_process';
import { blue, bold, cyan, green, red } from 'colorette';
import { setupShutdownHandlers, updateArkServer } from 'root/entrypoint/server.ts';
import { checkAndUpdateServerApi } from 'root/entrypoint/api.ts';
import { tailLogs } from 'root/entrypoint/logging.ts';
import { envVars } from 'root/entrypoint/types.ts';
// import { installPlugins } from './plugins.js';

/**
 * Process command line arguments
 */
export const processCommandLineArgs = (): boolean => {
  if (process.argv.length > 2) {
    const args = process.argv.slice(2);
    console.log(blue(`Executing command: ${args.join(' ')}`));
    execSync(args.join(' '), { stdio: 'inherit' });
    return true;
  }
  return false;
};

/**
 * Ensure all ENV variables are set
 */
const ensureEnvVariables = (): void => {
  console.log(blue('Checking environment variables...'));
  for (const [key, value] of Object.entries(envVars)) {
    if (!Bun.env[key] || !value) {
      throw new Error(`Environment variable ${key} is not set`);
    }
  }
  console.log(green('✅ All environment variables are set'));
};

/**
 * Main execution function
 */
const main = async (): Promise<void> => {
  console.log(bold(cyan('🚀 Starting ARK Server Container')));

  // If command is provided, run it and exit
  if (processCommandLineArgs()) {
    console.log(green('Command executed successfully, exiting'));
    process.exit(0);
  }

  // Ensure all ENV variables are set
  try {
    ensureEnvVariables();
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(bold(red(`❌ Environment check failed: ${errorMessage}`)));
    process.exit(1);
  }

  // Setup graceful shutdown handlers
  console.log(blue('Setting up shutdown handlers...'));
  setupShutdownHandlers();

  // Update ARK Server
  console.log(blue('Checking for ARK server updates...'));
  updateArkServer();

  // Check and update server API
  console.log(blue('Checking server API status...'));
  await checkAndUpdateServerApi();

  // Install plugins (uncomment when needed)
  // await installPlugins();

  console.log(bold(green('✅ Server initialization complete')));
  console.log(
    `${cyan('------------------------')} ${bold("Server is ready. Use 'manager' command to manage the server.")} ${cyan('------------------------')}`,
  );

  // Start tail logs
  console.log(blue('Starting log monitoring...'));
  tailLogs();
};

// Error handling
process.on('uncaughtException', (err: Error) => {
  console.error(bold(red(`❌ Uncaught exception: ${err.message}`)));
  console.error(err);
  process.exit(1);
});

// Run the main function
main().catch((err: Error) => {
  console.error(bold(red(`❌ Error during server startup: ${err.message}`)));
  console.error(err);
  process.exit(1);
});
