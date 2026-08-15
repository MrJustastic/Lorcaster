/**
 * @typedef MigrationContext
 * @property {import('sequelize').QueryInterface} queryInterface
 * @property {import('../Logger')} logger
 *
 * @typedef MigrationOptions
 * @property {MigrationContext} context
 */

const migrationVersion = '2.35.2'
const migrationName = `${migrationVersion}-add-hot-path-indexes`
const loggerPrefix = `[${migrationVersion} migration]`

const indexes = [
  {
    table: 'podcastEpisodes',
    name: 'podcast_episodes_podcast_id',
    fields: ['podcastId']
  },
  {
    table: 'playbackSessions',
    name: 'playback_sessions_user_updated',
    fields: ['userId', 'updatedAt']
  }
]

async function up({ context: { queryInterface, logger } }) {
  logger.info(`${loggerPrefix} UPGRADE BEGIN: ${migrationName}`)
  for (const index of indexes) {
    await addIndexIfMissing(queryInterface, logger, index)
  }
  logger.info(`${loggerPrefix} UPGRADE END: ${migrationName}`)
}

async function down({ context: { queryInterface, logger } }) {
  logger.info(`${loggerPrefix} DOWNGRADE BEGIN: ${migrationName}`)
  for (const index of indexes) {
    await removeIndexIfExists(queryInterface, logger, index)
  }
  logger.info(`${loggerPrefix} DOWNGRADE END: ${migrationName}`)
}

async function addIndexIfMissing(queryInterface, logger, index) {
  const existing = await queryInterface.showIndex(index.table)
  if (existing.some((i) => i.name === index.name)) {
    logger.info(`${loggerPrefix} index ${index.name} already exists on ${index.table}`)
    return
  }
  logger.info(`${loggerPrefix} adding index ${index.name} on ${index.table}(${index.fields.join(', ')})`)
  await queryInterface.addIndex(index.table, {
    name: index.name,
    fields: index.fields
  })
}

async function removeIndexIfExists(queryInterface, logger, index) {
  const existing = await queryInterface.showIndex(index.table)
  if (!existing.some((i) => i.name === index.name)) {
    return
  }
  await queryInterface.removeIndex(index.table, index.name)
}

module.exports = { up, down }
