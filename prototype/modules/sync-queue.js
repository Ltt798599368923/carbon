export async function flushPendingActions(actions, request) {
  if (!actions.length) return [];
  const remaining = [];
  for (const action of actions) {
    try {
      await request('/api/v1/actions', { method: 'POST', body: JSON.stringify(action) });
    } catch {
      remaining.push(action);
    }
  }
  return remaining;
}
