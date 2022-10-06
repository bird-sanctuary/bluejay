'''
Attempts to auto format assembler code by the following rules:
* Replace all tabs with whitespaces
* Replace multiple ;  with single ;
* Replace multiple empty lines with single empty line
* Find longest fields
'''

import os
import re
import sys

if len(sys.argv) < 2:
    print("Usage %s SOURCE_FILE" % (sys.argv[0]))
    sys.exit()

path = sys.argv[1]

processExtensions = ["asm", "inc"]
excludeDirs= ["build", "tools", "Silabs"]
spaces = 2
offsetInlineComments = 50

noIndent = ["IF", "ELSE", "ELSEIF", "MACRO", "$if", "$include", "$set"]
increaseDepth = ["IF", "MACRO", "$if"]
decreaseDepth = ["ENDIF", "ENDM", "$endif"]
temporaryDecreaseDepth = ["ELSE", "ELSEIF"]
processPaths = []
#suffix = ".asmb"
suffix = ""

# Collect all files to be processed
for root, dirs, files in os.walk(path):
    dirs[:] = [d for d in dirs if d not in excludeDirs]
    for file in files:
        extension = file.split(".")[-1]
        if extension in processExtensions:
            path = os.path.join(root, file)
            processPaths.append(path)


maxLength = [0, 0]

def cleanup(line):
    line = line.strip()

    # Replace tabs in all lines (even in comments)
    line = re.sub('\t+', ' ', line)
    if not line.startswith(";"):
        # Replace muliple spaces with one
        line = re.sub(' +', ' ', line)

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
    file = open("%s%s" % (path, suffix), 'w')
    for line in cleanLines:
        fields = line.split(" ")

        field0 = fields[0]
        field1 = fields[1] if (len(fields) > 1) else None

        # We leave block comments as they are apart from indendation
        if not line.startswith(";"):
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
