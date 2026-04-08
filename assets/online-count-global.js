(function(){
  var MIN = 800;
  var MAX = 900;
  var KEY = 'alexia_online_now_value';
  var TS_KEY = 'alexia_online_now_ts';
  var INTERVAL = 60000;

  function clamp(n){ return Math.max(MIN, Math.min(MAX, n)); }
  function randInt(min, max){ return Math.floor(Math.random() * (max - min + 1)) + min; }
  function now(){ return Date.now(); }
  function readNum(key){
    try {
      var v = parseInt(localStorage.getItem(key), 10);
      return Number.isFinite(v) ? v : null;
    } catch(e){ return null; }
  }
  function writeState(value, ts){
    try {
      localStorage.setItem(KEY, String(value));
      localStorage.setItem(TS_KEY, String(ts));
    } catch(e){}
  }
  function getInitial(){
    var saved = readNum(KEY);
    var ts = readNum(TS_KEY);
    if(saved === null || ts === null){
      saved = randInt(MIN, MAX);
      ts = now();
      writeState(saved, ts);
    }
    return { value: saved, ts: ts };
  }
  function nextValue(current){
    var delta = Math.max(1, Math.round(current * 0.10));
    return clamp(randInt(current - delta, current + delta));
  }
  function getState(forceAdvance){
    var state = getInitial();
    var t = now();
    if(forceAdvance || (t - state.ts) >= INTERVAL){
      state = { value: nextValue(state.value), ts: t };
      writeState(state.value, state.ts);
    }
    return state;
  }
  function applyCount(count){
    var sels = [
      '.online-count', '.online-now-count', '[data-online-now-count]', '[data-alexia-online-count]',
      '#global-online-count', '#onlineCount', '#online-count', '.site-nav-final__online span:last-child'
    ];
    var seen = new Set();
    sels.forEach(function(sel){
      document.querySelectorAll(sel).forEach(function(el){
        if(seen.has(el)) return;
        seen.add(el);
        el.textContent = String(count);
      });
    });
  }
  function render(forceAdvance){
    applyCount(getState(!!forceAdvance).value);
  }
  function start(){
    render(false);
    setInterval(function(){ render(true); }, INTERVAL);
  }
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, {once:true});
  else start();
})();
