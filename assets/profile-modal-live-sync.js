(function(){
  'use strict';
  var STORAGE_PROFILE = 'alexia_forum_profile_v1';
  var STORAGE_STATE = 'alexia_profile_state_v2';
  var STORAGE_USER_ID = 'alexia_profile_user_id_v1';
  var modalTimer = null;
  var remoteVideosPromise = null;
  var remoteVideosCache = null;
  var remoteVideosAt = 0;

  function readProfile(){
    try { return JSON.parse(localStorage.getItem(STORAGE_PROFILE) || '{}') || {}; }
    catch(e){ return {}; }
  }

  function readState(){
    try {
      var raw = JSON.parse(localStorage.getItem(STORAGE_STATE) || '{}') || {};
      raw.stats = raw.stats || {};
      return {
        total_time_seconds: Number(raw.stats.total_time_seconds || 0) || 0,
        total_videos_watched: Number(raw.stats.total_videos_watched || raw.stats.videos_viewed_count || 0) || 0,
        videos_viewed_count: Number(raw.stats.videos_viewed_count || raw.stats.total_videos_watched || 0) || 0,
        score: Number(raw.stats.score || 0) || 0
      };
    } catch(e) {
      return { total_time_seconds: 0, total_videos_watched: 0, videos_viewed_count: 0, score: 0 };
    }
  }

  function formatDuration(totalSeconds){
    var s = Math.max(0, Number(totalSeconds || 0) || 0);
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    if (h > 0) return h + 'h ' + m + 'm';
    return Math.floor(s / 60) + 'm';
  }

  function getOpenModalBody(){
    return document.querySelector('#community-profile-modal.open .modal-body');
  }

  function getModalUsername(modal){
    if (!modal) return '';
    var h = modal.querySelector('h3');
    return ((h && h.textContent) || '').trim().toLowerCase();
  }

  function getLocalUsername(){
    var p = readProfile();
    return String(p.nickname || '').trim().toLowerCase();
  }

  function getTrackedUserId(){
    try {
      var raw = JSON.parse(localStorage.getItem(STORAGE_STATE) || '{}') || {};
      raw.meta = raw.meta || {};
      return String(raw.meta.user_id || raw.meta.local_user_id || localStorage.getItem(STORAGE_USER_ID) || '').trim();
    } catch(e) {
      return String(localStorage.getItem(STORAGE_USER_ID) || '').trim();
    }
  }

  function getModalSupabaseClient(){
    if (!window.supabase || !window.supabase.createClient || !window.SUPABASE_URL || !window.SUPABASE_KEY) return null;
    if (!window.__alexiaCommunityModalClient) {
      window.__alexiaCommunityModalClient = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_KEY, {
        auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,storageKey:'alexia-comments-auth-v2'}
      });
    }
    return window.__alexiaCommunityModalClient;
  }

  function writeViewedCountToCache(count){
    try {
      var raw = JSON.parse(localStorage.getItem(STORAGE_STATE) || '{}') || {};
      raw.stats = raw.stats || {};
      raw.stats.total_videos_watched = Number(count || 0) || 0;
      raw.stats.videos_viewed_count = Number(count || 0) || 0;
      localStorage.setItem(STORAGE_STATE, JSON.stringify(raw));
    } catch(e) {}
  }

  async function fetchRemoteVideoCount(){
    try {
      var client = getModalSupabaseClient();
      if (!client) return null;
      var trackedUserId = getTrackedUserId();
      var session = await client.auth.getSession();
      var authUser = session && session.data && session.data.session && session.data.session.user;
      var userId = authUser && authUser.id ? String(authUser.id) : trackedUserId;
      if (!userId) return null;
      var result = await client.from('user_video_views')
        .select('video_slug', { count: 'exact', head: true })
        .eq('user_id', userId)
        .eq('viewed', true);
      var count = Number(result && result.count);
      return isFinite(count) ? count : null;
    } catch(e) {
      return null;
    }
  }

  async function getFreshRemoteVideoCount(){
    if (remoteVideosCache !== null && (Date.now() - remoteVideosAt) < 15000) return remoteVideosCache;
    if (remoteVideosPromise) return remoteVideosPromise;
    remoteVideosPromise = fetchRemoteVideoCount().then(function(count){
      if (count !== null) {
        remoteVideosCache = count;
        remoteVideosAt = Date.now();
        writeViewedCountToCache(count);
      }
      return count;
    }).finally(function(){
      remoteVideosPromise = null;
    });
    return remoteVideosPromise;
  }

  function updateStatByLabel(modal, labelRegex, value){
    if (!modal) return false;
    var spans = modal.querySelectorAll('span');
    for (var i = 0; i < spans.length; i++) {
      var label = (spans[i].textContent || '').trim();
      if (!labelRegex.test(label)) continue;
      var stat = spans[i].closest('.stat');
      if (!stat) stat = spans[i].parentElement;
      if (!stat) continue;
      var strong = stat.querySelector('strong');
      if (strong) {
        strong.textContent = value;
        return true;
      }
    }
    return false;
  }

  async function applyLiveStats(){
    var modal = getOpenModalBody();
    if (!modal) return;
    var modalUser = getModalUsername(modal);
    var localUser = getLocalUsername();
    if (!modalUser || !localUser || modalUser !== localUser) return;
    var stats = readState();
    updateStatByLabel(modal, /^score$|activity score/i, String(stats.score || 0));
    updateStatByLabel(modal, /watch time|total time|time on site|time in the house/i, formatDuration(stats.total_time_seconds));
    var remoteCount = await getFreshRemoteVideoCount();
    var videos = remoteCount !== null ? remoteCount : (stats.total_videos_watched || stats.videos_viewed_count || 0);
    updateStatByLabel(modal, /videos watched|watched videos|videos/i, String(videos));
  }

  function startModalSync(){
    if (modalTimer) return;
    modalTimer = setInterval(function(){
      if (!getOpenModalBody()) {
        clearInterval(modalTimer);
        modalTimer = null;
        return;
      }
      applyLiveStats();
    }, 5000);
  }

  function onPotentialOpen(){
    setTimeout(function(){
      applyLiveStats();
      if (getOpenModalBody()) startModalSync();
    }, 80);
    setTimeout(function(){
      applyLiveStats();
      if (getOpenModalBody()) startModalSync();
    }, 300);
  }

  document.addEventListener('click', onPotentialOpen, true);
  window.addEventListener('alexia-profile-cache-updated', applyLiveStats);
  window.addEventListener('storage', function(ev){
    if (ev.key === STORAGE_STATE || ev.key === STORAGE_PROFILE) applyLiveStats();
  });
  document.addEventListener('DOMContentLoaded', function(){ applyLiveStats(); });
})();
