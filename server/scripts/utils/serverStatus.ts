/**
 * Server Status Utility
 * Tools for checking ARK server status and ensuring it's in the right state
 * for certain operations
 */

import { spawn } from 'child_process';
import { bold, green, red, yellow } from 'colorette';

interface ServerStatusOptions {
  /** Optional list of process names to consider as server processes */
  processNames?: Array<string>;
  /** Whether to display status messages to console */
  silent?: boolean;
}

/**
 * Checks if the ARK server is currently running
 * @returns Promise resolving to true if server is running, false otherwise
 */
export const isServerRunning = async (options: ServerStatusOptions = {}): Promise<boolean> => {
  const { processNames = ['ShooterGameServer'], silent = false } = options;

  try {
    // Use ps to check for running server processes
    const ps = spawn('ps', ['aux']);

    const result = await new Promise<boolean>((resolve) => {
      let output = '';

      ps.stdout.on('data', (data) => {
        output += data.toString();
      });

      ps.on('close', () => {
        // Check if any of the process names are found in the ps output
        const isRunning = processNames.some((processName) => output.includes(processName));

        if (!silent) {
          if (isRunning) {
            console.log(yellow('ARK server is currently running.'));
          } else {
            console.log(green('ARK server is not running.'));
          }
        }

        resolve(isRunning);
      });
    });

    return result;
  } catch (error) {
    if (!silent) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(red(`Error checking server status: ${errorMessage}`));
    }
    // Default to assuming it's running if we can't determine status
    // This is safer for operations that require the server to be stopped
    return true;
  }
};

/**
 * Ensures the server is in the expected running state before proceeding
 * @param shouldBeRunning Whether the server should be running
 * @returns Promise resolving to true if server is in expected state
 */
const ensureServerState = async (shouldBeRunning: boolean, options: ServerStatusOptions = {}): Promise<boolean> => {
  const isRunning = await isServerRunning({ ...options, silent: true });

  if (isRunning === shouldBeRunning) {
    return true;
  }

  if (shouldBeRunning) {
    console.error(bold(red('Error: ARK Server is not running, but it needs to be for this operation.')));
    console.log(yellow('Please start the server before proceeding.'));
  } else {
    console.error(bold(red('Error: ARK Server is currently running, but it needs to be stopped for this operation.')));
    console.log(yellow('Please stop the server before proceeding.'));
  }

  return false;
};

/**
 * Convenience method to ensure server is stopped before proceeding
 * @returns Promise resolving to true if server is stopped
 */
export const ensureServerStopped = async (options: ServerStatusOptions = {}): Promise<boolean> => ensureServerState(false, options);

/**
 * Convenience method to ensure server is running before proceeding
 * @returns Promise resolving to true if server is running
 */
export const ensureServerRunning = async (options: ServerStatusOptions = {}): Promise<boolean> => ensureServerState(true, options);
