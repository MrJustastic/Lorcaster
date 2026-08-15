const Path = require('path')
const fs = require('../libs/fsExtra')
const stream = require('stream')
const Logger = require('../Logger')
const { resizeImage } = require('../utils/ffmpegHelpers')
const { encodeUriPath } = require('../utils/fileUtils')
const Database = require('../Database')

class CacheManager {
  constructor() {
    this.CachePath = null
    this.CoverCachePath = null
    this.ImageCachePath = null
    this.ItemCachePath = null
    /** @type {Map<string, Promise<string|null>>} */
    this.inFlightResizes = new Map()
  }

  /**
   * Create cache directory paths if they dont exist
   */
  async ensureCachePaths() {
    // Creates cache paths if necessary and sets owner and permissions
    this.CachePath = Path.join(global.MetadataPath, 'cache')
    this.CoverCachePath = Path.join(this.CachePath, 'covers')
    this.ImageCachePath = Path.join(this.CachePath, 'images')
    this.ItemCachePath = Path.join(this.CachePath, 'items')

    try {
      await fs.ensureDir(this.CachePath)
      await fs.ensureDir(this.CoverCachePath)
      await fs.ensureDir(this.ImageCachePath)
      await fs.ensureDir(this.ItemCachePath)
    } catch (error) {
      Logger.error(`[CacheManager] Failed to create cache directories at "${this.CachePath}": ${error.message}`)
      throw new Error(`[CacheManager] Failed to create cache directories at "${this.CachePath}"`, { cause: error })
    }
  }

  async handleCoverCache(res, libraryItemId, options = {}) {
    const format = options.format || 'webp'
    const width = options.width || 400
    const height = options.height || null

    res.type(`image/${format}`)

    const cachePath = Path.join(this.CoverCachePath, `${libraryItemId}_${width}${height ? `x${height}` : ''}`) + '.' + format

    if (await fs.pathExists(cachePath)) {
      return this.sendCachedImage(res, cachePath)
    }

    const writtenFile = await this.resizeOnce(cachePath, async () => {
      const coverPath = await Database.libraryItemModel.getCoverPath(libraryItemId)
      if (!coverPath || !(await fs.pathExists(coverPath))) return null
      return resizeImage(coverPath, cachePath, width, height)
    })
    if (!writtenFile) return res.sendStatus(404)

    return this.sendCachedImage(res, writtenFile)
  }

  /**
   * Deduplicate concurrent ffmpeg resizes for the same cache path.
   * @param {string} cachePath
   * @param {() => Promise<string|null>} producer
   * @returns {Promise<string|null>}
   */
  resizeOnce(cachePath, producer) {
    const existing = this.inFlightResizes.get(cachePath)
    if (existing) return existing
    const pending = Promise.resolve()
      .then(producer)
      .finally(() => this.inFlightResizes.delete(cachePath))
    this.inFlightResizes.set(cachePath, pending)
    return pending
  }

  /**
   * Stream a cached image with validators so clients can skip the body.
   * @param {import('express').Response} res
   * @param {string} filePath
   */
  async sendCachedImage(res, filePath) {
    if (global.XAccel) {
      const encodedURI = encodeUriPath(global.XAccel + filePath)
      Logger.debug(`Use X-Accel to serve static file ${encodedURI}`)
      return res.status(204).header({ 'X-Accel-Redirect': encodedURI }).send()
    }

    let stat
    try {
      stat = await fs.stat(filePath)
    } catch (error) {
      Logger.error(`[CacheManager] Failed to stat cache file "${filePath}"`, error)
      return res.sendStatus(500)
    }

    const etag = `W/"${stat.size.toString(16)}-${Math.floor(stat.mtimeMs).toString(16)}"`
    res.set({
      'Cache-Control': 'private, max-age=86400',
      ETag: etag,
      'Last-Modified': stat.mtime.toUTCString()
    })
    if (res.req && (res.req.headers['if-none-match'] === etag || (res.req.headers['if-modified-since'] && Date.parse(res.req.headers['if-modified-since']) >= stat.mtimeMs))) {
      return res.status(304).end()
    }

    const r = fs.createReadStream(filePath)
    const ps = new stream.PassThrough()
    stream.pipeline(r, ps, (err) => {
      if (err) {
        Logger.error(`[CacheManager] Failed to stream cache file "${filePath}"`, err)
        if (!res.headersSent) res.sendStatus(500)
      }
    })
    return ps.pipe(res)
  }

  purgeCoverCache(libraryItemId) {
    return this.purgeEntityCache(libraryItemId, this.CoverCachePath)
  }

  purgeImageCache(entityId) {
    return this.purgeEntityCache(entityId, this.ImageCachePath)
  }

  async purgeEntityCache(entityId, cachePath) {
    if (!entityId || !cachePath) return []
    return Promise.all(
      (await fs.readdir(cachePath)).reduce((promises, file) => {
        if (file.startsWith(entityId)) {
          Logger.debug(`[CacheManager] Going to purge ${file}`)
          promises.push(this.removeCache(Path.join(cachePath, file)))
        }
        return promises
      }, [])
    )
  }

  removeCache(path) {
    if (!path) return false
    return fs.pathExists(path).then((exists) => {
      if (!exists) return false
      return fs
        .unlink(path)
        .then(() => true)
        .catch((err) => {
          Logger.error(`[CacheManager] Failed to remove cache "${path}"`, err)
          return false
        })
    })
  }

  async purgeAll() {
    Logger.info(`[CacheManager] Purging all cache at "${this.CachePath}"`)
    if (await fs.pathExists(this.CachePath)) {
      await fs.remove(this.CachePath).catch((error) => {
        Logger.error(`[CacheManager] Failed to remove cache dir "${this.CachePath}"`, error)
      })
    }
    await this.ensureCachePaths()
  }

  async purgeItems() {
    Logger.info(`[CacheManager] Purging items cache at "${this.ItemCachePath}"`)
    if (await fs.pathExists(this.ItemCachePath)) {
      await fs.remove(this.ItemCachePath).catch((error) => {
        Logger.error(`[CacheManager] Failed to remove items cache dir "${this.ItemCachePath}"`, error)
      })
    }
    await this.ensureCachePaths()
  }

  /**
   *
   * @param {import('express').Response} res
   * @param {String} authorId
   * @param {{ format?: string, width?: number, height?: number }} options
   * @returns
   */
  async handleAuthorCache(res, authorId, options = {}) {
    const format = options.format || 'webp'
    const width = options.width || 400
    const height = options.height || null

    res.type(`image/${format}`)

    const cachePath = Path.join(this.ImageCachePath, `${authorId}_${width}${height ? `x${height}` : ''}`) + '.' + format

    if (await fs.pathExists(cachePath)) {
      return this.sendCachedImage(res, cachePath)
    }

    const writtenFile = await this.resizeOnce(cachePath, async () => {
      const author = await Database.authorModel.findByPk(authorId)
      if (!author || !author.imagePath || !(await fs.pathExists(author.imagePath))) return null
      return resizeImage(author.imagePath, cachePath, width, height)
    })
    if (!writtenFile) return res.sendStatus(404)

    return this.sendCachedImage(res, writtenFile)
  }
}
module.exports = new CacheManager()
