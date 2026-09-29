"""Small original 5x7 arcade font, rasterized by Mojo (no font library)."""

def glyph(code: Int) -> UInt64:
    # Rows are packed from top to bottom, five bits per row.
    if code == 65: return 15621670449  # A
    if code == 66: return 32801506878  # B
    if code == 67: return 16660316687  # C
    if code == 68: return 32801080894  # D
    if code == 69: return 33840644639  # E
    if code == 70: return 33840644624  # F
    if code == 71: return 16660547119  # G
    if code == 72: return 18842895921  # H
    if code == 73: return 33424543903  # I
    if code == 74: return 7585483340  # J
    if code == 75: return 18879369809  # K
    if code == 76: return 17734058527  # L
    if code == 77: return 19182306865  # M
    if code == 78: return 19119394417  # N
    if code == 79: return 15621211694  # O
    if code == 80: return 32801505808  # P
    if code == 81: return 15621215821  # Q
    if code == 82: return 32801509969  # R
    if code == 83: return 16660235326  # S
    if code == 84: return 33424543876  # T
    if code == 85: return 18842437166  # U
    if code == 86: return 18842436932  # V
    if code == 87: return 18842572458  # W
    if code == 88: return 18834663985  # X
    if code == 89: return 18834657412  # Y
    if code == 90: return 33321787935  # Z
    if code == 48: return 15623448110  # 0
    if code == 49: return 4701950094  # 1
    if code == 50: return 15603929375  # 2
    if code == 51: return 32247317566  # 3
    if code == 52: return 2359917634  # 4
    if code == 53: return 33840628798  # 5
    if code == 54: return 15587034670  # 6
    if code == 55: return 33321787656  # 7
    if code == 56: return 15621113390  # 8
    if code == 57: return 15621129262  # 9
    if code == 47: return 1143087376  # /
    if code == 45: return 1015808  # -
    if code == 46: return 198  # .
    if code == 58: return 207624384  # :
    if code == 43: return 139432064  # +
    return 0
