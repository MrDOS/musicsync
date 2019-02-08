#! /usr/bin/env python3

from datetime import datetime
from dateutil.relativedelta import relativedelta
import glob
import json
import os
import re
import sys
import urllib.parse
import urllib.request

class LastFmApi:
    API_ROOT = 'http://ws.audioscrobbler.com/2.0/'

    PERIOD_OVERALL = 'overall'
    PERIOD_7_DAYS = '7day'
    PERIOD_1_MONTHS = '1month'
    PERIOD_3_MONTHS = '3month'
    PERIOD_6_MONTHS = '6month'
    PERIOD_12_MONTHS = '12month'

    def __init__(self, api_key):
        self._api_key = api_key

    def _call(self, method, **kwargs):
        params = {'method': method, 'format': 'json', 'api_key': self._api_key}
        params.update(kwargs)
        query = urllib.parse.urlencode(params)
        request = urllib.request.urlopen('%s?%s' % (LastFmApi.API_ROOT, query))
        return json.loads(request.read().decode())

    def userGetTopAlbums(self, user, period=PERIOD_OVERALL, limit=50, page=1):
        return self._call('user.gettopalbums', user=user, period=period, limit=limit, page=page)

    def userGetTopArtists(self, user, period=PERIOD_OVERALL, limit=50, page=1):
        return self._call('user.gettopartists', user=user, period=period, limit=limit, page=page)

    def userGetWeeklyArtistChart(self, user, time_from=None, time_to=None):
        return self._call('user.getweeklyartistchart', **{
            'user': user,
            'from': time_from.timestamp() if time_from is not None and time_to is not None else None,
            'to': time_to.timestamp() if time_from is not None and time_to is not None else None})

def usage(error=None):
    if error is not None:
        print('Error: %s' % error, file=sys.stderr)
    print('Usage: LASTFM_API_KEY=... python3 %s lastfm-user' % sys.argv[0], file=sys.stderr if error is not None else sys.stdout)
    sys.exit(1 if error is not None else 0)

if __name__ == '__main__':
    if len(sys.argv) > 1 and re.match(r'--?h(elp)?', sys.argv[1]):
        usage()

    if len(sys.argv) < 2:
        usage('no Last.fm username given!')

    if 'LASTFM_API_KEY' not in os.environ:
        usage('Last.fm API key must be given via the "LASTFM_API_KEY" environment variable!')

    lastfm_api_key = os.environ['LASTFM_API_KEY']
    username = sys.argv[1]

    api = LastFmApi(lastfm_api_key)

    artists = set()
    for artist in api.userGetTopArtists(username, period=LastFmApi.PERIOD_6_MONTHS, limit=500)['topartists']['artist']:
        artist_name = artist['name']

        # Any “feat.” or “with” in the name is almost certainly the track
        # artist, not the album artist.
        artist_name = re.sub(r' (feat\.|with|vs\.) .*', '', artist_name, flags=re.IGNORECASE)

        artists.add(artist_name)

    for artist in sorted(list(artists), key=str.lower):
        print('%s' % artist)
