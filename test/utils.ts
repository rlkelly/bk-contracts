export function calculatePayout(amount: number, odds: number) {
    if (odds < 0) {
      return Math.floor(amount * 100 / (-1 * odds));
    }
    return Math.floor((amount * odds) / 100);
}
