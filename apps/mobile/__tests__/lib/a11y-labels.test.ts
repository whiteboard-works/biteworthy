import { readFileSync, readdirSync, statSync } from 'fs';
import { join } from 'path';

/**
 * An accessibilityLabel is what VoiceOver and TalkBack say out loud. The
 * app used them as test hooks for a while, so a screen reader announced
 * "restaurant-himalayan-kitchen" instead of the restaurant's name. Test
 * hooks belong in testID; a label must be words a person would say.
 */
function sources(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sources(path);
    return path.endsWith('.tsx') ? [path] : [];
  });
}

// A kebab-case identifier, quoted or in a template: "account-link",
// {`open-item-${item.id}`}. Real labels contain spaces or capitals.
const CODE_LABEL =
  /accessibilityLabel=(?:"([a-z0-9]+(?:-[a-z0-9]+)+)"|\{`((?:[a-z0-9]+-)+\$\{[^`]*)`\})/;

describe('accessibility labels', () => {
  const files = sources(join(__dirname, '../../app'));

  it('finds the screens to check', () => {
    expect(files.length).toBeGreaterThan(5);
  });

  it.each(files)('%s gives screen readers words, not test hooks', (file) => {
    const offenders = readFileSync(file, 'utf8')
      .split('\n')
      .filter((line) => CODE_LABEL.test(line));
    expect(offenders).toEqual([]);
  });
});
