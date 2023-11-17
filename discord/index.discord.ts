import { Client, GatewayIntentBits } from 'discord.js';
import utc from 'dayjs/plugin/utc.js';
import timezone from 'dayjs/plugin/timezone.js';
import { extend } from 'dayjs';
import log from 'utils/log-utils.ts';
import rulesEmbedDiscord from 'discord/rulesEmbed.discord.ts';
import aboutEmbedDiscord from 'discord/aboutEmbed.discord.ts';
import handleVerificationReactionDiscord from 'discord/handleVerificationReaction.discord.ts';

/**
 * This will extend dayjs with the utc and timezone plugins. Throughout the codebase.
 */
extend(utc);
extend(timezone);

const intents: Array<GatewayIntentBits> = [
  GatewayIntentBits.Guilds,
  GatewayIntentBits.GuildMembers,
  GatewayIntentBits.GuildPresences,
  GatewayIntentBits.GuildMessages,
  GatewayIntentBits.GuildMessageReactions,
  GatewayIntentBits.MessageContent,
];

try {
  const client = new Client({ intents });
  await client.login(Bun.env.DISCORD_TOKEN);

  client.on('ready', async () => {
    log.info(`Logged in as ${client.user?.tag}!`);

    const server = await client.guilds.fetch({ guild: '706560580244471929' });

    await aboutEmbedDiscord(server);
    await rulesEmbedDiscord(server);

    await handleVerificationReactionDiscord(client, server);
  });

  client.on('error', (error) => {
    log.error('Error:', error);
  });
} catch (error) {
  log.error('Error:', error);
}