import { execSync } from 'node:child_process';

// Function to extract zip file using system unzip
export const extractZip = (zipFile: string, destination: string): void => {
  try {
    console.log(`Extracting ${zipFile} to ${destination}...`);
    // Use system unzip command (faster and more reliable in Linux environments)
    execSync(`unzip -o "${zipFile}" -d "${destination}"`, { stdio: 'inherit' });
  } catch (unzipError) {
    console.error(`System unzip command failed: ${unzipError instanceof Error ? unzipError.message : 'Unknown error'}`);

    // Try again with additional options
    try {
      console.log('Attempting extraction with additional unzip options...');
      // -j option flattens the directory structure, which can help with problematic ZIPs
      execSync(`unzip -o -j "${zipFile}" -d "${destination}"`, { stdio: 'inherit' });
    } catch (_finalError) {
      throw new Error(`Failed to extract ${zipFile}: Unzip command failed. Make sure 'unzip' is installed in your container.`);
    }
  }
};
