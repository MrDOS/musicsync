#! /usr/bin/env python3

import editdistance
import fileinput
import os
import os.path
import re
import sys

def find_albums(library_path, search_albums):
    artists = [artist for artist in os.listdir(library_path) if os.path.isdir(os.path.join(library_path, artist))]
    artist_albums = {artist: [album for album in os.listdir(os.path.join(library_path, artist)) if os.path.isdir(os.path.join(library_path, artist, album))] for artist in artists}

    for artist, album in search_albums:
        match_artists = [(match_artist, editdistance.eval(sanitize_name(artist), sanitize_name(match_artist))) for match_artist in artists]
        closest_artist, artist_distance = sorted(match_artists, key=lambda match_artist: match_artist[1])[0]

        if artist_distance > len(artist) * .5:
            print('No artist match found for "%s - %s" (closest option was "%s"). Skipping.' % (artist, album, closest_artist), file=sys.stderr)
            continue

        match_albums = [(match_album, editdistance.eval(sanitize_name(album), sanitize_name(match_album))) for match_album in artist_albums[closest_artist]]
        closest_album, album_distance = sorted(match_albums, key=lambda match_album: match_album[1])[0]

        if album_distance > len(album) * .5:
            print('No album match found for "%s - %s" (closest option was "%s - %s"). Skipping.' % (artist, album, closest_artist, closest_album), file=sys.stderr)
            continue

        print(os.path.join(library_path, closest_artist, closest_album))

def sanitize_name(name):
    name = name.lower()
    return re.sub(r' \(\d+(;(?P<qualifier> [^)]+))?\)$', '\g<qualifier>', name).lower()

def usage(error=None):
    if error is not None:
        print('Error: %s' % error)
    print('Usage: python3 %s library_path <search_albums' % sys.argv[0])
    sys.exit(1 if error is not None else 0)

if __name__ == '__main__':
    if len(sys.argv) > 1 and re.match(r'--?h(elp)?', sys.argv[1]):
        usage()

    if len(sys.argv) < 2:
        usage('no library path given!')

    library_path = sys.argv[1]
    if not os.path.isdir(library_path):
        usage('could not locate music library at %s!' % library_path)

    search_albums = []
    for line in fileinput.input(files=sys.argv[2:]):
        search_albums.append(line.strip().split(' - ', 1))

    find_albums(library_path, search_albums)
