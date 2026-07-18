class Autotune:
    """Reference note frequencies used by Applio's realtime pitch autotune."""

    def __init__(self):
        self.note_dict = [440.0 * (2.0 ** (semitone / 12.0)) for semitone in range(-38, 16)]
