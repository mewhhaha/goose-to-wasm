"""Read retained JSON measurements, including gzip-compressed reports."""

import gzip
import json


def decode_report(data):
    if data.startswith(b"\x1f\x8b"):
        data = gzip.decompress(data)
    return json.loads(data)
