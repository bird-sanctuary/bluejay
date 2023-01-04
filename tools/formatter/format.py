'''
Attempts to auto format assembler code by the following rules:
* Replace all tabs with whitespaces
* Replace multiple ;  with single ;
* Replace multiple empty lines with single empty line
* Find longest fields
'''
import argparse
import filecmp
import os
import re
import sys

parser = argparse.ArgumentParser(description="Format and lint 8051 assembler files.")
parser.add_argument("path", metavar="PATH", type=str,
                    help="directory to search for files")
parser.add_argument("--extensions", dest="extensions", nargs="+",
                    default=["asm", "inc"],
                    help="list of file extension to parse")
parser.add_argument("--exclude", dest="exclude", nargs="+",
                    default=["build", "tools", "Silabs"],
                    help="list of directories to exclude")
parser.add_argument("--suffix", dest="suffix",
                    default="", help="suffix for formatted file, default overwrites current file")
parser.add_argument("--spaces", dest="spaces",
                    default=2, help="spaces per level of indent")
parser.add_argument("--comment-offset", dest="commentOffset",
                    default=50, help="offset for comments from beginning of the line")
parser.add_argument("--lint", dest="lint", action="store_true",
                    default=False, help="lint files")

args = parser.parse_args()

path = args.path
processExtensions = args.extensions
excludeDirs = args.exclude
suffix = args.suffix
spaces = args.spaces
offsetInlineComments = args.commentOffset
lint = args.lint

if lint:
    suffix = ".asmb"

noIndent = ["IF", "ELSE", "ELSEIF", "MACRO", "$if", "$include", "$set"]
increaseDepth = ["IF", "MACRO", "$if"]
decreaseDepth = ["ENDIF", "ENDM", "$endif"]
temporaryDecreaseDepth = ["ELSE", "ELSEIF"]
maxLength = [0, 0]

def cleanup(line):
    line = line.strip()

    # Replace tabs in all lines (even in comments)
    line = re.sub('\t+', ' ', line)
    if not line.startswith(";"):
        # Replace muliple spaces with one unless in quotes
        line = re.sub(r'("[^"]*")| +', lambda m: m.group(1) if m.group(1) else ' ', line)

        # Replace multiple semicolons with one
        line = re.sub(';+', ';', line)

        # Replace comma space with just a comma
        line = re.sub(', ', ',', line)

        fields = line.split(" ")
        field0 = fields[0]
        field1 = fields[1] if (len(fields) > 1) else None

        # Find long strings to indent calculation
        if (not field1 or not field1.startswith(tuple(noIndent))) and not field0.endswith(":"):
            length = len(field0)
            if length > maxLength[0] and not field0.startswith(tuple(noIndent)):
                maxLength[0] = length

            # Only cound if filed 1 is available and does not contain a comma
            if field1 and "," not in field1:
                # Only count field 1 if there is one following
                if len(fields) > 2 and fields[2] != ";":
                    # Only count if field 0 should have indent
                    if not field0.startswith(tuple(noIndent)):
                        length = len(field1)
                        if length > maxLength[1]:
                            maxLength[1] = length

    return line

# Collect all files to be processed
processPaths = []
for root, dirs, files in os.walk(path):
    dirs[:] = [d for d in dirs if d not in excludeDirs]
    for file in files:
        extension = file.split(".")[-1]
        if extension in processExtensions:
            path = os.path.join(root, file)
            processPaths.append(path)

for path in processPaths:
    '''
    In the first run we find out what our longest fields are and do some base
    sanitation.
    '''
    depth = 0

    cleanLines = []
    lastEmpty = False
    maxLength = [0, 0]

    file = open(path, 'r')
    lines = file.readlines()
    for line in lines:
        line = cleanup(line)

        # Prevent two empty lines after each other
        if line != "" or not lastEmpty:
          cleanLines.append(line)

        lastEmpty = False
        if line == "":
          lastEmpty = True

    file.close()

    # Reformat all available lines
    targetPath = "%s%s" % (path, suffix)
    file = open(targetPath, 'w')
    for line in cleanLines:
        if line != "":
            fields = line.split(" ")

            field0 = fields[0]
            field1 = fields[1] if (len(fields) > 1) else None

            # We leave block comments as they are apart from indendation
            if not line.startswith(";") and len(fields) > 1:
                if field0 not in noIndent and field1 not in noIndent:
                    # Append spaces to field 0
                    append0 = maxLength[0] - len(field0) - (depth * spaces)
                    fields[0] = "%s%s" % (field0, " " * append0)

                    # Append spaced to field 1
                    if len(fields) > 1 and field1 != ";" and "," not in field1:
                        append1 = maxLength[1] - len(field1)

                        # Compensate for lines where field 0 is longer due to indendation
                        if append0 < 0:
                            append1 += append0

                        fields[1] = "%s%s" % (field1, " " * append1)

                    if len(fields) > 1 and field1 != ";" and "," in field1:
                        fields[1] = re.sub(',', ', ', field1)

                line = " ".join(fields)

            if field0 in decreaseDepth or field1 in decreaseDepth:
                depth -= 1

            # Calculate space prefix
            spacePrefix = depth * spaces
            if field0 in temporaryDecreaseDepth:
                spacePrefix -= spaces

            line = "%s%s" % (" " * spacePrefix, line)

            # Align all inline comments
            fields = line.split(";")
            if not line.startswith(";") and fields[0].strip() != "":
                if len(fields) > 1:
                    append = offsetInlineComments - len(fields[0])
                    fields[0] = "%s%s" % (fields[0], " " * append)
                    line = ";".join(fields)

            if field0 in increaseDepth or field1 in increaseDepth:
                depth += 1

        file.write("%s\n" % line)

    file.close()

    if lint:
        match = filecmp.cmp(path, targetPath)
        os.unlink(targetPath)

        if not match:
            print("Failed linting %s" % path)
            sys.exit(1)
