/*
 * v3.12 Break-time guidance for the official e-staffing daily form.
 * Read-only on page load and when time fields change.
 * The official rest field is changed ONLY by an explicit user tap of
 * the "休憩の目安を入力" action or by the site's own original controls.
 * Never triggers a save, application, request, or automatic field input.
 */
(() => {
  'use strict';
  if (location.hostname !== 'm.e-staffing.ne.jp' || !location.pathname.startsWith('/s/')) return;

  const form = document.querySelector('form[name="TMSINP01ActionForm"]');
  if (!form || form.dataset.etcBreakAssistant === '1') return;
  const start = form.querySelector('input[name="startTime"]');
  const end = form.querySelector('input[name="endTime"]');
  const rest = form.querySelector('input[name="rstTime"]');
  if (!start || !end || !rest) return;
  form.dataset.etcBreakAssistant = '1';

  const parseHHMM = value => {
    const raw = String(value ?? '').trim();
    const match = raw.match(/^(\d{1,2}):(\d{2})$/) || raw.match(/^(\d{1,2})(\d{2})$/);
    if (!match) return null;
    const h = Number(match[1]), m = Number(match[2]);
    return h > 23 || m > 59 ? null : h * 60 + m;
  };
  const proposedBreak = () => {
    const a = parseHHMM(start.value), b = parseHHMM(end.value);
    if (a === null || b === null) return null;
    let elapsed = b - a;
    if (elapsed < 0) elapsed += 1440;
    if (elapsed === 0 || elapsed > 16 * 60) return null;
    // This is a conservative guidance tier based on elapsed shift span,
    // not a statement that the employee actually took this break.
    return elapsed > 8 * 60 ? 60 : elapsed > 6 * 60 ? 45 : 0;
  };

  const display = document.createElement('div');
  display.className = 'etc-break-assistant';
  display.setAttribute('role', 'status');
  const caption = document.createElement('span');
  caption.className = 'etc-break-assistant-caption';
  const action = document.createElement('button');
  action.type = 'button';
  action.className = 'etc-break-assistant-button';
  action.textContent = '休憩の目安を入力';
  const note = document.createElement('p');
  note.className = 'etc-break-assistant-note';
  note.textContent = '休憩の目安を表示しますが、休憩欄には自動入力しません。入力する場合はボタンを押し、実際に取得した休憩時間を確認してください。';

  display.append(caption, action);

  // Reading guidance is safe on load/time changes; writing is NOT.
  const updateGuidance = () => {
    const suggested = proposedBreak();
    if (suggested === null) {
      caption.textContent = '開始・終了時刻が揃うと休憩の目安を表示します';
    } else if (suggested === 0) {
      caption.textContent = '休憩の目安：勤務時間を確認してください';
    } else {
      caption.textContent = '休憩の目安：' + suggested + '分（実際の休憩とは別）';
    }
    action.disabled = suggested === null || suggested === 0 ||
                      rest.disabled || rest.readOnly;
  };

  // Only user-triggered action changes the site's actual restTime field.
  action.addEventListener('click', () => {
    const suggested = proposedBreak();
    if (!suggested || rest.disabled || rest.readOnly) return;
    const current = String(rest.value ?? '').trim();
    if (current === String(suggested)) return;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    if (setter) setter.call(rest, String(suggested));
    else rest.value = String(suggested);
    rest.dispatchEvent(new Event('input', { bubbles: true }));
    rest.dispatchEvent(new Event('change', { bubbles: true }));
    caption.textContent = '休憩目安' + suggested + '分を入力しました。実際の取得時間を確認してください。';
    updateGuidance();
  });

  start.addEventListener('input', updateGuidance);
  start.addEventListener('change', updateGuidance);
  end.addEventListener('input', updateGuidance);
  end.addEventListener('change', updateGuidance);
  rest.addEventListener('input', updateGuidance);
  rest.addEventListener('change', updateGuidance);

  // Keep official fields and controls intact; this is a hint only.
  const target = rest.closest('.etc-form-card') ||
                 rest.closest('table')?.parentElement || rest.parentElement;
  if (target) {
    target.append(display, note);
    const style = document.createElement('style');
    style.textContent = 
      '.etc-break-assistant{display:flex;gap:8px;align-items:center;justify-content:space-between;flex-wrap:wrap;margin-top:11px;padding:10px 12px;border-radius:12px;background:var(--e-blue-wash,rgba(0,122,255,.10));color:var(--e-ink,inherit);}' +
      '.etc-break-assistant-caption{font-size:12px;font-weight:650;line-height:1.5;flex:1;min-width:130px;}' +
      '.etc-break-assistant-button{min-height:36px!important;padding:6px 11px!important;border:0!important;border-radius:10px!important;background:var(--e-blue,#007aff)!important;color:#fff!important;font-size:12px!important;font-weight:700!important;}' +
      '.etc-break-assistant-button:disabled{opacity:.5;}' +
      '.etc-break-assistant-note{color:var(--e-muted,#6e6e73);font-size:11px;line-height:1.6;margin:7px 3px 0;}';
    (document.head || document.documentElement).appendChild(style);
  }
  updateGuidance(); // Never mutates startTime/endTime/rstTime.
})();
