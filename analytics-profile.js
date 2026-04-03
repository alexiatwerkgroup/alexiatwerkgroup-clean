(function(){
  'use strict';

  if (window.__alexiaProfileTrackerStarted) return;
  window.__alexiaProfileTrackerStarted = true;

  var SUPABASE_URL = 'https://vieqniahusdrfkpcuqsn.supabase.co';
  var SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZpZXFuaWFodXNkcmZrcGN1cXNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM0MTk2NjksImV4cCI6MjA4ODk5NTY2OX0.Ox8gUp0g-aYRvI2Zj6PWxx5unO3m3sEtal0OKLvPSkQ';

  var STORAGE_USER_ID = 'alexia_profile_user_id_v1';
  var STORAGE_STATE = 'alexia_profile_state_v2';

  var SITE_TICK_MS = 5000;
  var FLUSH_INTERVAL_MS = 15000;
  var ACTIVITY_WINDOW_MS = 30000;
  var SCORE_TICK_SECONDS = 15;
  var SCORE_PER_ACTIVE_TICK = 1;
  var SCORE_PER_VIDEO = 5;
  var MAX_PROGRESS_DELTA_SECONDS = 3.5;

  function safeNumber(value){
    return Number(value || 0) || 0;
  }

  function ensureLocalUserId(){
    try {
      var id = localStorage.getItem(STORAGE_USER_ID);
      if (!id) {
        if (window.crypto && window.crypto.randomUUID) id = window.crypto.randomUUID();
        else id = 'u_' + Math.random().toString(36).slice(2) + Date.now().toString(36);
        localStorage.setItem(STORAGE_USER_ID, id);
      }
      return id;
    } catch (e) {
      return 'u_fallback_' + Date.now();
    }
  }

  function normalizeState(raw){
    raw = raw && typeof raw === 'object' ? raw : {};
    raw.viewedVideos = raw.viewedVideos && typeof raw.viewedVideos === 'object' ? raw.viewedVideos : {};
    raw.stats = raw.stats && typeof raw.stats === 'object' ? raw.stats : {};
    raw.meta = raw.meta && typeof raw.meta === 'object' ? raw.meta : {};

    raw.stats.total_time_seconds = safeNumber(raw.stats.total_time_seconds);
    raw.stats.video_watch_seconds = safeNumber(raw.stats.video_watch_seconds);
    raw.stats.total_videos_watched = safeNumber(raw.stats.total_videos_watched || raw.stats.videos_viewed_count);
    raw.stats.videos_viewed_count = safeNumber(raw.stats.videos_viewed_count || raw.stats.total_videos_watched);
    raw.stats.score = safeNumber(raw.stats.score);
    raw.stats.updated_at = String(raw.stats.updated_at || raw.stats.last_update || '');
    raw.meta.local_user_id = String(raw.meta.local_user_id || '');
    raw.meta.user_id = String(raw.meta.user_id || '');
    raw.meta.last_remote_sync_at = String(raw.meta.last_remote_sync_at || '');

    return raw;
  }

  function loadState(){
    try {
      return normalizeState(JSON.parse(localStorage.getItem(STORAGE_STATE) || '{}'));
    } catch (e) {
      return normalizeState({});
    }
  }

  function saveState(state){
    try {
      localStorage.setItem(STORAGE_STATE, JSON.stringify(normalizeState(state)));
    } catch (e) {}
  }

  function getBadgeLabel(videoCount){
    var count = safeNumber(videoCount);
    if (count >= 50) return 'ADDICTED';
    if (count >= 10) return 'EXPLORER';
    return 'VISITOR';
  }

  function emitProfileCacheUpdate(state, source){
    var normalized = normalizeState(state);
    try {
      window.dispatchEvent(new CustomEvent('alexia-profile-cache-updated', {
        detail: {
          source: source || 'cache',
          userId: normalized.meta.user_id || normalized.meta.local_user_id || '',
          stats: {
            total_time_seconds: normalized.stats.total_time_seconds,
            video_watch_seconds: normalized.stats.video_watch_seconds,
            total_videos_watched: normalized.stats.total_videos_watched,
            videos_viewed_count: normalized.stats.videos_viewed_count,
            score: normalized.stats.score,
            updated_at: normalized.stats.updated_at || ''
          },
          badge: getBadgeLabel(normalized.stats.total_videos_watched || normalized.stats.videos_viewed_count)
        }
      }));
    } catch (e) {}
  }

  function setState(state, source){
    state = normalizeState(state);
    saveState(state);
    emitProfileCacheUpdate(state, source);
  }

  function nowIso(){
    return new Date().toISOString();
  }

  function loadSupabase(cb){
    if (window.supabase && window.supabase.createClient) return cb();
    var existing = document.querySelector('script[data-alexia-supabase-loader="1"]');
    if (existing) {
      existing.addEventListener('load', cb, { once: true });
      return;
    }
    var script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
    script.defer = true;
    script.setAttribute('data-alexia-supabase-loader', '1');
    script.onload = cb;
    document.head.appendChild(script);
  }

  function loadScriptOnce(src, marker, cb){
    if (marker()) return cb();
    var existing = document.querySelector('script[data-src="' + src + '"]');
    if (existing) {
      existing.addEventListener('load', cb, { once: true });
      return;
    }
    var script = document.createElement('script');
    script.src = src;
    script.async = true;
    script.setAttribute('data-src', src);
    script.onload = cb;
    document.head.appendChild(script);
  }

  function findVideoSlug(){
    var path = String(location.pathname || '/').replace(/\/+$/, '');
    var slug = path.split('/').pop() || 'home';
    return slug.replace(/\.html?$/i, '') || 'home';
  }

  function findMainIframe(){
    return document.getElementById('main-video-player') ||
      document.querySelector('iframe[src*="youtube.com/embed/"], iframe[src*="youtube-nocookie.com/embed/"], iframe[src*="player.vimeo.com/video/"]');
  }

  function findVideoId(){
    var iframe = findMainIframe();
    var video = document.querySelector('video');
    if (iframe) {
      var src = String(iframe.getAttribute('src') || '');
      var youtube = src.match(/embed\/([^?&#"']+)/i);
      var vimeo = src.match(/video\/([^?&#"']+)/i);
      if (youtube && youtube[1]) return youtube[1];
      if (vimeo && vimeo[1]) return vimeo[1];
    }
    if (video) {
      var directSrc = String(video.currentSrc || video.getAttribute('src') || '');
      if (directSrc) return directSrc.split('/').pop().split('?')[0];
    }
    return findVideoSlug();
  }

  function isVideoLikePage(){
    var path = String(location.pathname || '');
    if (/\/playlist\//i.test(path)) return true;
    return !!(findMainIframe() || document.querySelector('video'));
  }

  var localUserId = ensureLocalUserId();
  var state = loadState();
  if (!state.meta.local_user_id) state.meta.local_user_id = localUserId;
  if (!state.meta.user_id) state.meta.user_id = localUserId;

  var userId = state.meta.user_id || localUserId;
  var pageUrl = String(location.pathname || '/');
  var videoSlug = findVideoSlug();
  var videoId = findVideoId();
  var videoLikePage = isVideoLikePage();
  var client = null;
  var lastInteractionAt = Date.now();
  var pendingSiteSeconds = 0;
  var pendingVideoWatchSeconds = 0;
  var pendingScore = 0;
  var scoreSecondBucket = 0;
  var markedViewed = !!state.viewedVideos[videoSlug];
  var flushPromise = null;
  var flushRequested = false;

  function markInteraction(){
    lastInteractionAt = Date.now();
  }

  ['mousemove', 'mousedown', 'keydown', 'touchstart', 'scroll', 'pointerdown'].forEach(function(eventName){
    window.addEventListener(eventName, markInteraction, { passive: true });
  });

  function isHumanActive(){
    return !document.hidden && (Date.now() - lastInteractionAt) <= ACTIVITY_WINDOW_MS;
  }

  function setViewedCount(count){
    var safe = safeNumber(count);
    state.stats.total_videos_watched = safe;
    state.stats.videos_viewed_count = safe;
  }

  function buildStatsUpsert(){
    return {
      user_id: userId,
      total_time_seconds: safeNumber(state.stats.total_time_seconds),
      video_watch_seconds: safeNumber(state.stats.video_watch_seconds),
      total_videos_watched: safeNumber(state.stats.total_videos_watched),
      videos_viewed_count: safeNumber(state.stats.videos_viewed_count),
      score: safeNumber(state.stats.score),
      last_update: nowIso(),
      updated_at: nowIso()
    };
  }

  async function resolveTrackedUserId(){
    if (!client || !client.auth || !client.auth.getSession) {
      userId = localUserId;
      state.meta.user_id = userId;
      return userId;
    }
    try {
      var session = await client.auth.getSession();
      var authUser = session && session.data && session.data.session && session.data.session.user;
      var nextUserId = authUser && authUser.id ? String(authUser.id) : localUserId;
      if (nextUserId !== userId) {
        if (userId === localUserId && nextUserId !== localUserId) {
          await migrateAnonStatsToAuth(nextUserId);
        }
        userId = nextUserId;
        state.meta.user_id = userId;
        setState(state, 'identity');
      }
    } catch (e) {
      userId = localUserId;
      state.meta.user_id = userId;
    }
    return userId;
  }

  async function migrateAnonStatsToAuth(authUserId){
    if (!client || !authUserId || authUserId === localUserId) return;
    try {
      await client.from('user_video_views')
        .update({ user_id: authUserId })
        .eq('user_id', localUserId);

      var anonStats = await client.from('user_stats').select('*').eq('user_id', localUserId).maybeSingle();
      var authStats = await client.from('user_stats').select('*').eq('user_id', authUserId).maybeSingle();

      var merged = normalizeState({
        viewedVideos: state.viewedVideos,
        stats: {
          total_time_seconds: Math.max(
            safeNumber(state.stats.total_time_seconds),
            safeNumber(anonStats && anonStats.data && anonStats.data.total_time_seconds),
            safeNumber(authStats && authStats.data && authStats.data.total_time_seconds)
          ),
          video_watch_seconds: Math.max(
            safeNumber(state.stats.video_watch_seconds),
            safeNumber(anonStats && anonStats.data && anonStats.data.video_watch_seconds),
            safeNumber(authStats && authStats.data && authStats.data.video_watch_seconds)
          ),
          total_videos_watched: Math.max(
            safeNumber(state.stats.total_videos_watched),
            safeNumber(anonStats && anonStats.data && (anonStats.data.videos_viewed_count || anonStats.data.total_videos_watched)),
            safeNumber(authStats && authStats.data && (authStats.data.videos_viewed_count || authStats.data.total_videos_watched))
          ),
          videos_viewed_count: Math.max(
            safeNumber(state.stats.videos_viewed_count),
            safeNumber(anonStats && anonStats.data && (anonStats.data.videos_viewed_count || anonStats.data.total_videos_watched)),
            safeNumber(authStats && authStats.data && (authStats.data.videos_viewed_count || authStats.data.total_videos_watched))
          ),
          score: Math.max(
            safeNumber(state.stats.score),
            safeNumber(anonStats && anonStats.data && anonStats.data.score),
            safeNumber(authStats && authStats.data && authStats.data.score)
          )
        },
        meta: state.meta
      });

      state.stats = merged.stats;
      state.meta.user_id = authUserId;
      var previousUserId = userId;
      userId = authUserId;
      await client.from('user_stats').upsert(buildStatsUpsert(), { onConflict: 'user_id' });
      userId = authUserId || previousUserId;
      setState(state, 'migration');
    } catch (e) {}
  }

  async function getRemoteViewedCount(){
    if (!client) return safeNumber(state.stats.videos_viewed_count || state.stats.total_videos_watched);
    try {
      var result = await client.from('user_video_views')
        .select('video_slug', { count: 'exact', head: true })
        .eq('user_id', userId)
        .eq('viewed', true);
      return safeNumber(result && result.count);
    } catch (e) {
      return safeNumber(state.stats.videos_viewed_count || state.stats.total_videos_watched);
    }
  }

  async function seedRemoteFromLocalIfNeeded(){
    if (!client) return;
    var localViewed = Object.keys(state.viewedVideos || {});
    if (!localViewed.length) return;

    var remoteCount = await getRemoteViewedCount();
    if (remoteCount > 0) return;

    for (var i = 0; i < localViewed.length; i++) {
      var slug = String(localViewed[i] || '').trim();
      if (!slug) continue;
      try {
        await client.from('user_video_views').upsert({
          user_id: userId,
          video_slug: slug,
          video_id: slug,
          watched_seconds: 30,
          viewed: true,
          last_seen_at: nowIso(),
          watched_at: nowIso()
        }, { onConflict: 'user_id,video_slug' });
      } catch (e) {}
    }
  }

  async function readRemoteSnapshot(){
    if (!client) return null;
    try {
      await resolveTrackedUserId();
      await seedRemoteFromLocalIfNeeded();

      var statsRes = await client.from('user_stats').select('*').eq('user_id', userId).maybeSingle();
      var row = statsRes && statsRes.data ? statsRes.data : {};
      var viewedCount = await getRemoteViewedCount();

      return {
        total_time_seconds: safeNumber(row.total_time_seconds),
        video_watch_seconds: safeNumber(row.video_watch_seconds),
        total_videos_watched: viewedCount || safeNumber(row.total_videos_watched || row.videos_viewed_count),
        videos_viewed_count: viewedCount || safeNumber(row.videos_viewed_count || row.total_videos_watched),
        score: safeNumber(row.score),
        updated_at: String(row.updated_at || row.last_update || '')
      };
    } catch (e) {
      return null;
    }
  }

  async function syncRemoteSnapshot(source){
    var remote = await readRemoteSnapshot();
    if (!remote) return;

    state.stats.total_time_seconds = Math.max(safeNumber(state.stats.total_time_seconds), safeNumber(remote.total_time_seconds));
    state.stats.video_watch_seconds = Math.max(safeNumber(state.stats.video_watch_seconds), safeNumber(remote.video_watch_seconds));
    state.stats.score = Math.max(safeNumber(state.stats.score), safeNumber(remote.score));
    setViewedCount(remote.videos_viewed_count || remote.total_videos_watched);
    state.stats.updated_at = remote.updated_at || nowIso();
    state.meta.last_remote_sync_at = nowIso();
    setState(state, source || 'remote-sync');
  }

  async function ensureRemoteStatsRow(){
    if (!client) return;
    try {
      await resolveTrackedUserId();
      await client.from('user_stats').upsert(buildStatsUpsert(), { onConflict: 'user_id' });
    } catch (e) {}
  }

  async function upsertVideoViewRow(secondsValue, viewed){
    if (!client || !videoLikePage) return null;
    try {
      await resolveTrackedUserId();
      var watchedSeconds = Math.max(0, Math.floor(safeNumber(secondsValue)));
      var payload = {
        user_id: userId,
        video_slug: videoSlug,
        video_id: String(videoId || videoSlug || ''),
        watched_seconds: watchedSeconds,
        viewed: !!viewed,
        last_seen_at: nowIso(),
        watched_at: viewed ? nowIso() : null
      };

      await client.from('user_video_views').upsert(payload, { onConflict: 'user_id,video_slug' });
      return payload;
    } catch (e) {
      return null;
    }
  }

  function getViewThresholdSeconds(duration){
    var d = safeNumber(duration);
    if (d > 0) return Math.min(30, Math.max(8, Math.round(d * 0.25)));
    return 30;
  }

  async function markVideoViewed(force){
    if (!videoLikePage || markedViewed) return;
    if (!force && playback.watchSeconds < getViewThresholdSeconds(playback.durationSeconds)) return;

    markedViewed = true;
    state.viewedVideos[videoSlug] = nowIso();
    state.stats.score = safeNumber(state.stats.score) + SCORE_PER_VIDEO;

    await upsertVideoViewRow(playback.watchSeconds, true);
    setViewedCount(await getRemoteViewedCount());
    state.stats.updated_at = nowIso();
    setState(state, 'video-viewed');
    await ensureRemoteStatsRow();
  }

  var playback = {
    watchSeconds: 0,
    durationSeconds: 0,
    playing: false,
    lastObservedTime: null,
    pollTimer: null,
    update: function(current, duration){
      if (typeof duration === 'number' && isFinite(duration) && duration > 0) {
        playback.durationSeconds = Math.max(playback.durationSeconds, duration);
      }
      if (typeof current !== 'number' || !isFinite(current)) return;

      if (playback.lastObservedTime === null) {
        playback.lastObservedTime = current;
        return;
      }

      var delta = current - playback.lastObservedTime;
      playback.lastObservedTime = current;

      if (delta <= 0 || delta > MAX_PROGRESS_DELTA_SECONDS) return;
      pendingVideoWatchSeconds += delta;
      playback.watchSeconds += delta;
      if (!markedViewed && playback.watchSeconds >= getViewThresholdSeconds(playback.durationSeconds)) {
        markVideoViewed(false);
      }
    },
    resetClock: function(current){
      playback.lastObservedTime = typeof current === 'number' && isFinite(current) ? current : null;
    },
    setPlaying: function(isPlaying, current){
      playback.playing = !!isPlaying;
      if (!playback.playing) playback.resetClock(current);
    }
  };

  function startPolling(fetchCurrent, fetchDuration){
    stopPolling();
    playback.pollTimer = window.setInterval(function(){
      Promise.all([fetchCurrent(), fetchDuration()]).then(function(values){
        playback.update(safeNumber(values[0]), safeNumber(values[1]));
      }).catch(function(){});
    }, 1000);
  }

  function stopPolling(){
    if (playback.pollTimer) {
      window.clearInterval(playback.pollTimer);
      playback.pollTimer = null;
    }
  }

  function attachHtmlVideoTracking(){
    var video = document.querySelector('video');
    if (!video) return false;

    function syncNow(){
      playback.update(safeNumber(video.currentTime), safeNumber(video.duration));
    }

    video.addEventListener('play', function(){
      playback.setPlaying(true, safeNumber(video.currentTime));
    });
    video.addEventListener('pause', function(){
      syncNow();
      playback.setPlaying(false, safeNumber(video.currentTime));
    });
    video.addEventListener('seeking', function(){
      playback.resetClock(safeNumber(video.currentTime));
    });
    video.addEventListener('timeupdate', syncNow);
    video.addEventListener('ended', function(){
      playback.update(safeNumber(video.duration || video.currentTime), safeNumber(video.duration));
      playback.setPlaying(false, safeNumber(video.duration || video.currentTime));
      markVideoViewed(true);
      flushStats(true);
    });
    return true;
  }

  function attachYouTubeTracking(iframe){
    if (!iframe) return false;
    var src = String(iframe.getAttribute('src') || '');
    if (!/youtube\.com\/embed\/|youtube-nocookie\.com\/embed\//i.test(src)) return false;

    loadScriptOnce('https://www.youtube.com/iframe_api', function(){
      return !!(window.YT && window.YT.Player);
    }, function(){
      function initPlayer(){
        if (!(window.YT && window.YT.Player)) {
          window.setTimeout(initPlayer, 200);
          return;
        }

        if (!iframe.id) iframe.id = 'alexia-yt-' + Math.random().toString(36).slice(2);
        var currentSrc = String(iframe.getAttribute('src') || '');
        if (currentSrc.indexOf('enablejsapi=1') === -1) {
          currentSrc += (currentSrc.indexOf('?') === -1 ? '?' : '&') + 'enablejsapi=1';
        }
        if (!/[?&]origin=/.test(currentSrc)) {
          currentSrc += '&origin=' + encodeURIComponent(location.origin);
        }
        iframe.setAttribute('src', currentSrc);

        var player;
        try {
          player = new window.YT.Player(iframe.id, {
            events: {
              onReady: function(){
                try {
                  playback.durationSeconds = Math.max(playback.durationSeconds, safeNumber(player.getDuration()));
                } catch (e) {}
              },
              onStateChange: function(event){
                var stateCode = safeNumber(event && event.data);
                if (stateCode === 1) {
                  playback.setPlaying(true, safeNumber(player.getCurrentTime()));
                  startPolling(
                    function(){ return Promise.resolve(player.getCurrentTime()); },
                    function(){ return Promise.resolve(player.getDuration()); }
                  );
                } else if (stateCode === 0) {
                  stopPolling();
                  playback.update(safeNumber(player.getDuration()), safeNumber(player.getDuration()));
                  playback.setPlaying(false, safeNumber(player.getDuration()));
                  markVideoViewed(true);
                  flushStats(true);
                } else {
                  stopPolling();
                  try { playback.update(safeNumber(player.getCurrentTime()), safeNumber(player.getDuration())); } catch (e) {}
                  playback.setPlaying(false, safeNumber(player.getCurrentTime()));
                }
              }
            }
          });
        } catch (e) {}
      }

      if (window.YT && window.YT.Player) initPlayer();
      else {
        var previous = window.onYouTubeIframeAPIReady;
        window.onYouTubeIframeAPIReady = function(){
          if (typeof previous === 'function') previous();
          initPlayer();
        };
      }
    });
    return true;
  }

  function attachVimeoTracking(iframe){
    if (!iframe) return false;
    var src = String(iframe.getAttribute('src') || '');
    if (!/player\.vimeo\.com\/video\//i.test(src)) return false;

    loadScriptOnce('https://player.vimeo.com/api/player.js', function(){
      return !!(window.Vimeo && window.Vimeo.Player);
    }, function(){
      if (!(window.Vimeo && window.Vimeo.Player)) return;
      try {
        var player = new window.Vimeo.Player(iframe);
        player.on('play', function(data){
          playback.setPlaying(true, safeNumber(data && data.seconds));
        });
        player.on('pause', function(data){
          playback.update(safeNumber(data && data.seconds), safeNumber(data && data.duration));
          playback.setPlaying(false, safeNumber(data && data.seconds));
        });
        player.on('timeupdate', function(data){
          playback.update(safeNumber(data && data.seconds), safeNumber(data && data.duration));
        });
        player.on('seeked', function(data){
          playback.resetClock(safeNumber(data && data.seconds));
        });
        player.on('ended', function(data){
          playback.update(safeNumber(data && data.duration), safeNumber(data && data.duration));
          playback.setPlaying(false, safeNumber(data && data.duration));
          markVideoViewed(true);
          flushStats(true);
        });
      } catch (e) {}
    });
    return true;
  }

  function attachPlaybackTracking(){
    if (attachHtmlVideoTracking()) return;
    var iframe = findMainIframe();
    if (!iframe) return;
    if (attachYouTubeTracking(iframe)) return;
    attachVimeoTracking(iframe);
  }

  async function flushStats(force){
    if (flushPromise) {
      flushRequested = flushRequested || !!force;
      return flushPromise;
    }

    flushPromise = (async function(){
      do {
        var mustFlush = !!force || flushRequested;
        flushRequested = false;
        force = false;

        if (!mustFlush && pendingSiteSeconds <= 0 && pendingVideoWatchSeconds <= 0 && pendingScore <= 0) continue;
        if (!client) continue;

        await resolveTrackedUserId();

        if (pendingSiteSeconds > 0) {
          state.stats.total_time_seconds = safeNumber(state.stats.total_time_seconds) + pendingSiteSeconds;
          pendingSiteSeconds = 0;
        }
        if (pendingVideoWatchSeconds > 0) {
          var wholeVideoSeconds = Math.floor(pendingVideoWatchSeconds);
          if (wholeVideoSeconds > 0) {
            state.stats.video_watch_seconds = safeNumber(state.stats.video_watch_seconds) + wholeVideoSeconds;
            pendingVideoWatchSeconds = pendingVideoWatchSeconds - wholeVideoSeconds;
          }
        }
        if (pendingScore > 0) {
          state.stats.score = safeNumber(state.stats.score) + pendingScore;
          pendingScore = 0;
        }
        state.stats.updated_at = nowIso();
        setState(state, 'flush-local');

        if (videoLikePage) {
          await upsertVideoViewRow(playback.watchSeconds, markedViewed);
          if (markedViewed) setViewedCount(await getRemoteViewedCount());
        }

        await ensureRemoteStatsRow();
        setState(state, 'flush-remote');
      } while (flushRequested);
    })().finally(function(){
      flushPromise = null;
    });

    return flushPromise;
  }

  function activeTick(){
    if (!isHumanActive()) return;
    pendingSiteSeconds += Math.round(SITE_TICK_MS / 1000);
    scoreSecondBucket += Math.round(SITE_TICK_MS / 1000);
    if (scoreSecondBucket >= SCORE_TICK_SECONDS) {
      var scoreUnits = Math.floor(scoreSecondBucket / SCORE_TICK_SECONDS);
      pendingScore += scoreUnits * SCORE_PER_ACTIVE_TICK;
      scoreSecondBucket = scoreSecondBucket % SCORE_TICK_SECONDS;
    }
    if (pendingSiteSeconds >= 15 || pendingScore >= 2 || pendingVideoWatchSeconds >= 10) {
      flushStats(false);
    }
  }

  function installLifecycleHooks(){
    setInterval(activeTick, SITE_TICK_MS);
    setInterval(function(){ flushStats(false); }, FLUSH_INTERVAL_MS);

    document.addEventListener('visibilitychange', function(){
      if (document.hidden) flushStats(true);
      else markInteraction();
    });
    window.addEventListener('focus', markInteraction);
    window.addEventListener('pagehide', function(){ flushStats(true); });
    window.addEventListener('beforeunload', function(){ flushStats(true); });
  }

  function start(){
    setState(state, 'boot');
    attachPlaybackTracking();
    installLifecycleHooks();
  }

  loadSupabase(function(){
    try {
      client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
          storageKey: 'alexia-comments-auth-v2'
        }
      });
    } catch (e) {
      client = null;
    }

    start();

    if (!client) return;

    resolveTrackedUserId()
      .then(function(){ return syncRemoteSnapshot('remote-initial'); })
      .then(function(){ return ensureRemoteStatsRow(); })
      .catch(function(){});
  });
})();
