#! /usr/bin/env python3

import editdistance
import fileinput
import os
import os.path
import re
import sys

def find_artists(library_path, search_artists):
    artists = [artist for artist in os.listdir(library_path) if os.path.isdir(os.path.join(library_path, artist))]

    for artist in search_artists:
        match_artists = [(match_artist, editdistance.eval(sanitize_name(artist), sanitize_name(match_artist))) for match_artist in artists]
        closest_artist, artist_distance = sorted(match_artists, key=lambda match_artist: match_artist[1])[0]

        if artist_distance > len(artist) * .5:
            print('No artist match found for "%s" (closest option was "%s"). Skipping.' % (artist, closest_artist), file=sys.stderr)
            continue

        print(os.path.join(library_path, closest_artist))

def sanitize_name(name):
    return re.sub(r'\(.+?\)', '', name).lower()

def usage(error=None):
    if error is not None:
        print('Error: %s' % error)
    print('Usage: python3 %s library_path <search_artists' % sys.argv[0])
    sys.exit(1 if error is not None else 0)

if __name__ == '__main__':
    if len(sys.argv) > 1 and re.match(r'--?h(elp)?', sys.argv[1]):
        usage()

    if len(sys.argv) < 2:
        usage('no library path given!')

    library_path = sys.argv[1]
    if not os.path.isdir(library_path):
        usage('could not locate music library at %s!' % library_path)

    search_artists = []
    for line in fileinput.input(files=sys.argv[2:]):
        search_artists.append(line.strip())

    find_artists(library_path, search_artists)