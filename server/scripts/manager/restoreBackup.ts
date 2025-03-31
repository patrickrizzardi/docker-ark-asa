#!/usr/bin/env bun
/**
 * ARK Server Restore Backup Utility
 * Restores a selected backup archive to the ARK saved game data
 */

import path from 'path';
import { existsSync, mkdirSync, readdirSync, rmSync, statSync } from 'fs';
import { spawn } from 'child_process';
import readline from 'readline';
import { blue, bold, cyan, green, magenta, red, yellow } from 'colorette';
import { ensureServerStopped } from 'utils/serverStatus.ts';
import { envVars } from 'root/entrypoint/types.ts';

const { BACKUP_PATH, ARK_DIR } = envVars;

const SAVED_DIR = path.join(ARK_DIR, 'ShooterGame/Saved');
const TEMP_EXTRACT_PATH = path.join(BACKUP_PATH, 'temp-extract');

/**
 * Creates a readline interface for user input
 */
const createReadlineInterface = (): readline.Interface =>
  readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

/**
 * Lists available backup files with numbers
 */
const listBackupFiles = (): Array<string> => {
  console.log(bold(blue('Available backup archives:')));

  try {
    // Get all backup files ending with .tar.gz
    const backupFiles = readdirSync(BACKUP_PATH)
      .filter((file) => file.endsWith('.tar.gz'))
      .sort((a, b) => {
        // Sort by modification time (newest first)
        try {
          const statA = statSync(path.join(BACKUP_PATH, a));
          const statB = statSync(path.join(BACKUP_PATH, b));
          return statB.mtime.getTime() - statA.mtime.getTime();
        } catch {
          return 0;
        }
      });

    if (backupFiles.length === 0) {
      console.log(yellow('No backup archives found.'));
      process.exit(0);
    }

    // Display backups with numbers
    backupFiles.forEach((file, index) => {
      console.log(`${magenta(`${index + 1})`)} ${cyan(file)}`);
    });

    return backupFiles;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(red(`Error listing backup files: ${errorMessage}`));
    process.exit(1);
  }
};

/**
 * Prompts the user to select a backup file
 */
const promptForBackupSelection = async (backupFiles: Array<string>): Promise<string> => {
  const rl = createReadlineInterface();

  try {
    const answer = await new Promise<string>((resolve) => {
      console.log(blue('\nEnter the number of the backup you want to restore:'));
      rl.question(cyan('> '), resolve);
    });

    rl.close();

    const selectedIndex = parseInt(answer, 10) - 1;

    if (isNaN(selectedIndex) || selectedIndex < 0 || selectedIndex >= backupFiles.length) {
      console.error(red('Invalid selection. Please enter a valid number.'));
      process.exit(1);
    }

    const selectedFile = backupFiles[selectedIndex] ?? '';
    if (!selectedFile) {
      console.error(red('Selected backup not found.'));
      process.exit(1);
    }

    return selectedFile;
  } catch (error) {
    rl.close();
    throw error;
  }
};

/**
 * Extracts a tar.gz archive
 */
const extractArchive = async (archivePath: string, extractPath: string): Promise<void> => {
  console.log(blue(`Extracting ${archivePath} to ${extractPath}...`));

  return new Promise((resolve, reject) => {
    // Ensure extract path exists
    if (!existsSync(extractPath)) {
      mkdirSync(extractPath, { recursive: true });
    }

    const tar = spawn('tar', ['-xzf', archivePath, '-C', extractPath]);

    tar.stdout.on('data', (data) => console.log(`tar: ${data}`));
    tar.stderr.on('data', (data) => console.error(red(`tar error: ${data}`)));

    tar.on('close', (code) => {
      if (code === 0) {
        console.log(green('Archive extracted successfully'));
        resolve();
      } else {
        reject(new Error(`tar process exited with code ${code}`));
      }
    });
  });
};

/**
 * Confirms with the user before restoring
 */
const confirmRestore = async (selectedBackup: string): Promise<boolean> => {
  const rl = createReadlineInterface();

  try {
    console.log(yellow(`\n⚠️  Warning: Restoring backup ${cyan(selectedBackup)} will overwrite current saved data!`));
    const answer = await new Promise<string>((resolve) => {
      rl.question(bold(yellow('Are you sure you want to proceed? (y/N): ')), resolve);
    });

    rl.close();
    return answer.toLowerCase() === 'y';
  } catch (_error) {
    rl.close();
    return false;
  }
};

/**
 * Ensures parent directory structure exists
 */
const ensureParentDirectoryExists = (targetDir: string): void => {
  console.log(blue('Creating parent directory structure if needed...'));
  const parentDir = path.dirname(targetDir);
  if (!existsSync(parentDir)) {
    console.log(yellow(`Parent directory ${parentDir} doesn't exist, creating...`));
    mkdirSync(parentDir, { recursive: true });
  }
};

/**
 * Extracts archive directly to final location
 */
const extractDirectlyToTarget = async (archivePath: string, targetDir: string): Promise<void> => {
  console.log(blue('Extracting directly to final location...'));
  return new Promise<void>((resolve, reject) => {
    const tarDirect = spawn('tar', ['-xzf', archivePath, '-C', path.dirname(targetDir)]);

    tarDirect.stdout.on('data', (data) => console.log(`tar: ${data}`));
    tarDirect.stderr.on('data', (data) => console.error(red(`tar error: ${data}`)));

    tarDirect.on('close', (code) => {
      if (code === 0) {
        console.log(green('Archive extracted successfully to final location'));
        resolve();
      } else {
        reject(new Error(`Direct extraction failed with code ${code}`));
      }
    });
  });
};

/**
 * Cleans up temporary extraction directory
 */
const cleanupTempDirectory = (): void => {
  console.log(blue('Cleaning up temporary files...'));
  if (existsSync(TEMP_EXTRACT_PATH)) {
    rmSync(TEMP_EXTRACT_PATH, { recursive: true, force: true });
  }
};

/**
 * Restores a backup archive to the saved directory
 */
const restoreBackup = async (selectedBackup: string): Promise<void> => {
  const archivePath = path.join(BACKUP_PATH, selectedBackup);

  try {
    // Extract archive to temp folder
    await extractArchive(archivePath, TEMP_EXTRACT_PATH);

    // Ensure parent directories exist then extract directly
    ensureParentDirectoryExists(SAVED_DIR);
    await extractDirectlyToTarget(archivePath, SAVED_DIR);

    // Clean up and report success
    cleanupTempDirectory();
    console.log(bold(green('✅ Backup restored successfully!')));
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(bold(red(`❌ Failed to restore backup: ${errorMessage}`)));
    cleanupTempDirectory();
    process.exit(1);
  }
};

/**
 * Main function to run the restore process
 */
const main = async (): Promise<void> => {
  try {
    console.log(bold(cyan('🔄 ARK Server Backup Restoration')));

    // Check if server is running
    console.log(blue('Checking server status...'));
    const serverStopped = await ensureServerStopped();
    if (!serverStopped) {
      console.error(bold(red('❌ Cannot proceed with backup restoration while the server is running.')));
      console.log(yellow('Please stop the ARK server first and try again.'));
      process.exit(1);
    }

    // List available backups
    const backupFiles = listBackupFiles();

    // Get user selection
    const selectedBackup = await promptForBackupSelection(backupFiles);
    console.log(blue(`Selected backup: ${cyan(selectedBackup)}`));

    // Confirm restore
    const confirmed = await confirmRestore(selectedBackup);
    if (!confirmed) {
      console.log(yellow('Restoration cancelled.'));
      process.exit(0);
    }

    // Restore the selected backup
    await restoreBackup(selectedBackup);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(bold(red(`❌ Backup restoration failed: ${errorMessage}`)));
    process.exit(1);
  }
};

// Execute the restore process
main().catch((error) => {
  const errorMessage = error instanceof Error ? error.message : String(error);
  console.error(bold(red(`❌ Unhandled error in restore process: ${errorMessage}`)));
  process.exit(1);
});
