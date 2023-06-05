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
                    default=4, help="spaces per level of indent")
parser.add_argument("--comment-offset", dest="commentOffset",
                    default=40, help="offset for comments from beginning of the line")
parser.add_argument("--lint", dest="lint", action="store_true",
                    default=False, help="lint files")
parser.add_argument("--indent-labels", dest="indentLabels", action="store_true",
                    default=False, help="Indent code after labels")
parser.add_argument("--indent-macros", dest="indentMacros", action="store_true",
                    default=False, help="Indent code within macros")
parser.add_argument("--min-indentation", dest="minIndentation",
                    default=1, help="Minimum indentation for all instructions")
parser.add_argument("--format-comments", dest="formatComments", action="store_true",
                    default=False, help="Attempt to format comments")


args = parser.parse_args()

path = args.path
processExtensions = args.extensions
excludeDirs = args.exclude
suffix = args.suffix
spaces = args.spaces
offsetInlineComments = args.commentOffset
lint = args.lint
indentLabels = args.indentLabels
indentMacros = args.indentMacros
minIndentation = args.minIndentation
formatComments = args.formatComments

if lint:
    suffix = ".asmb"

noIndent = ["AT", "IF", "ELSE", "ELSEIF", "MACRO", "ENDM", "$if", "$endif", "$set", "EQU", "DB", "DS", "END", "$include", "$set"]
indentInIf = ["$include", "$set", "EQU", "AT"]
labelNoBreak = [";", "DS", "DB"]
increaseDepth = ["IF"]
decreaseDepth = ["ENDIF"]
temporaryDecreaseDepth = ["ELSE", "ELSEIF"]
nestedSameDepth = ["IF", "ENDIF"]
resetLabel = ["MACRO", "ENDM", "$include", ";****"]
maxLength = [0, 0]

if indentMacros:
    increaseDepth.append("MACRO")
    decreaseDepth.append("ENDM")

def cleanup(line):
    line = line.strip()


    if not line.startswith(";"):
        # Replace tabs in all lines
        line = re.sub('\t+', ' ', line)

        # Replace muliple spaces with one unless in quotes
        line = re.sub(r'("[^"]*")| +', lambda m: m.group(1) if m.group(1) else ' ', line)

        # Replace multiple semicolons with one
        line = re.sub(';+', ';', line)

        # Replace comma with comma space
        line = re.sub(', +', ',', line)

        # Add space after pre-processor directive
        line = re.sub(r'\$set\(', '$set (', line)

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

    else:
        line = re.sub('\t', ' ' * spaces, line)

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
    sawLabel = False
    inBanner = False

    cleanLines = []
    formattedLinesRough = []
    formattedLines = []

    lastEmpty = False
    maxLength = [0, 0]
    ifDepth = 0

    file = open(path, 'r')
    lines = file.readlines()
    for line in lines:
        line = cleanup(line)

        # split label and non comment line into two lines
        match = re.match(r"([\w\s]+\:)(.+)", line)
        if(match):
            field0 = match.group(1).strip()
            field1 = match.group(2).strip()

            if (
                not field1.startswith(";") and
                not field1.startswith("DS") and
                not field1.startswith("DB")
            ):
                cleanLines.append(field0)
                cleanLines.append(field1)

            else:
                cleanLines.append(line)

            continue

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
        lineIsLabel = False
        lineIsComment = False

        # Empty line
        if line == "":
            inBanner = False

        if line != "":
            fields = line.split(" ")

            if line.startswith(";"):
                lineIsComment = True

            if inBanner:
                if not line.startswith(";"):
                    inBanner = False

            if line.startswith(";****"):
                inBanner = True


            field0 = fields[0]
            field1 = fields[1] if (len(fields) > 1) else None

            if field0.endswith(":"):
                if not field1 or field1.startswith(";"):
                    lineIsLabel = True
                    sawLabel = True

            # We leave block comments as they are apart from indendation
            if not line.startswith(";") and len(fields) > 1:
                if field0 not in noIndent and field1 not in noIndent:
                    # Append spaces to field 0
                    # append0 = maxLength[0] - len(field0) - (depth * spaces)
                    append0 = 4 - len(field0)
                    fields[0] = "%s%s" % (field0, " " * append0)

                    # Append spaced to field 1
                    if len(fields) > 1 and field1 != ";" and "," not in field1:
                        #append1 = maxLength[1] - len(field1)
                        append1 = 0

                        # Compensate for lines where field 0 is longer due to indendation
                        if append0 < 0:
                            append1 += append0

                        fields[1] = "%s%s" % (field1, " " * append1)

                    if len(fields) > 1 and field1 != ";" and "," in field1:
                        fields[1] = re.sub(',', ', ', field1)

                line = " ".join(fields)
                line = line.rstrip()

            if field0 in decreaseDepth or field1 in decreaseDepth:
                # Nested IFs are not further indented
                if field0 == "ENDIF":
                    ifDepth -= 1
                    if ifDepth == 0:
                        depth -= 1
                else:
                    depth -= 1

            if sawLabel and (field0 in resetLabel or field1 in resetLabel):
                sawLabel = False
                depth -= 1

            if sawLabel and indentLabels:
                if depth == 0:
                    depth += 1

            if depth < 0:
                depth = 0

            # Calculate space prefix
            spacePrefix = depth * spaces

            if field0 in temporaryDecreaseDepth:
                spacePrefix -= spaces

            if lineIsLabel and spacePrefix > 0:
                spacePrefix = 0

            if inBanner:
                spacePrefix = 0

            # Do not further indent nested ifs
            if ifDepth > 0:
                if field0 in nestedSameDepth:
                    spacePrefix -= spaces

            if spacePrefix == 0:
                if (
                    field0 not in noIndent and
                    field1 not in noIndent and
                    field0 not in decreaseDepth and
                    not lineIsLabel and
                    not lineIsComment
                ):
                    spacePrefix = spaces * minIndentation

            if spacePrefix == 0 and ifDepth > 0:
                if field0 in indentInIf or field1 in indentInIf:
                    spacePrefix = spaces * minIndentation

            line = "%s%s" % (" " * spacePrefix, line)

            # Align all inline comments
            fields = line.split(";")
            if not line.startswith(";") and fields[0].strip() != "":
                if len(fields) > 1:
                    append = offsetInlineComments - len(fields[0])
                    fields[0] = "%s%s" % (fields[0], " " * append)
                    line = ";".join(fields)

            if field0 in increaseDepth or field1 in increaseDepth:
                # Nested IFs should not further be indented
                if field0 == "IF":
                    ifDepth += 1
                    if ifDepth == 1:
                        depth += 1
                else:
                    depth += 1

        formattedLinesRough.append(line)

    if formatComments:
        inBanner = False
        lineCount = len(formattedLinesRough)
        index = 0
        while index < lineCount:
            line = formattedLinesRough[index]

            if line.startswith(";"):
                if line.startswith(";**** "):
                    # While in Banner, just push comment lines
                    inBanner = True

                if inBanner:
                    formattedLines.append(line)
                    index += 1

                else:
                    # find first line that is not a comment (or empty) and apply
                    # indentation to all previous lines
                    offset = 1
                    while (
                        formattedLinesRough[index + offset].startswith(";") or
                        formattedLinesRough[index + offset] == ""
                    ):
                        offset += 1

                    spacePrefix = formattedLinesRough[index + offset]
                    spaceCount = len(spacePrefix) - len(spacePrefix.lstrip())

                    targetIndex = index + offset
                    while index < targetIndex:
                        line = formattedLinesRough[index]
                        if line != "":
                            line = "%s%s" % (" " * spaceCount, line)

                        formattedLines.append(line)
                        index += 1

            else:
                inBanner = False
                formattedLines.append(line)
                index += 1
    else:
        formattedLines = formattedLinesRough

    if formattedLines[-1] != "":
        formattedLines.append("")

    file.write("\n".join(formattedLines))
    file.close()

    if lint:
        match = filecmp.cmp(path, targetPath)
        os.unlink(targetPath)

        if not match:
            print("Failed linting %s" % path)
            sys.exit(1)
