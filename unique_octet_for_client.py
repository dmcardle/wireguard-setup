#!/usr/bin/env python3

import sys


def perfect_hash_octet(name: str, all_names: list[str]) -> int:
    """Returns a unique IP address octet for the given `name`.
    """
    assert len(set(all_names)) == len(all_names)
    assert len(all_names) <= 254
    i = all_names.index(name)
    # The final octet of the IPv4 address should not be zero. It also cannot be
    # one because that's reserved for the server.
    octet = i + 2
    assert 1 < octet < 255
    return octet


if __name__ == '__main__':
    client_name = sys.argv[1]
    all_names = sys.argv[2:]
    print(perfect_hash_octet(client_name, all_names))
