PROFILE = "/sim/profile"


def journal(*args):
    with open("/sim/journal", "a") as f:
        f.write("\t".join(args) + "\n")
