export type CreateEnum<T> = T[keyof T];

export interface PluginConfig {
  latestRelease: string;
  url: string;
  additionalFiles: Array<string>;
}

export type Plugins = Record<string, PluginConfig>;

export const CDN_URL = 'https://cdn.redact.digital/ark';

// Configuration
export const ARK_SERVER_API_LATEST_RELEASE = '1.17';

// Environment variables
const { ARK_DIR, STEAM_DIR, ASA_APPID, LOG_FILE, GAME_LOG_FILE, API_LOG_FILE, WINE_LOG_FILE, BACKUP_PATH, MAX_BACKUPS } = Bun.env;
export const envVars = <const>{
  ARK_DIR,
  STEAM_DIR,
  ASA_APPID,
  LOG_FILE,
  GAME_LOG_FILE,
  API_LOG_FILE,
  WINE_LOG_FILE,
  BACKUP_PATH,
  MAX_BACKUPS,
};
export type TEnvVars = CreateEnum<typeof envVars>;

// Plugin definitions
export const plugins: Plugins = {
  ArkShop: {
    latestRelease: '1.06',
    url: `${CDN_URL}/ArkShop`,
    additionalFiles: ['config.json', 'Commented.json'],
  },
  TurretManagerFREE: {
    latestRelease: '1.08',
    url: `${CDN_URL}/TurretManagerFREE`,
    additionalFiles: ['config.json'],
  },
  AdvancedMessagesAscended: {
    latestRelease: '1.2',
    url: `${CDN_URL}/AdvancedMessagesAscended`,
    additionalFiles: ['config.json', 'config_help.json'],
  },
};
