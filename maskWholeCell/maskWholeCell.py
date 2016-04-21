#! /usr/bin/env python

import os
import re
import array
import glob
import sys
import fileinput
import numpy as np
from scipy import misc
from optparse import OptionParser
from subprocess import Popen, call, PIPE
from sys import stderr, exit, argv

def usage(errstr):
    print ""
    print "ERROR: %s" % errstr
    print ""
    p.print_help()
    print ""
    exit(1)

if __name__ == "__main__":
    p = OptionParser(usage = "%prog [options] file.mrc file.mod path_seg") 

    p.add_option("-R", "--R", dest = "pointreduction", metavar = "VALUE",
                 help = "Value for point reduction during contour generation "
                        "with imodauto. Must be a value between 0-1, where 1 "
                        "will remove 100% of the points.")

    p.add_option("-P", "--P", dest = "passes", metavar = "VALUE",
                 help = "Number of passes through empty slices to perform "
                        "during meshing with imodmesh. (DEFAULT = 0)")

    p.add_option("--color", dest = "color", metavar = "R,G,B",
                 help = "Color for the output objects, in R,G,B, where R, G, "
                        "and B range from 0-1. If no color is specified, the "
                        "output objects will maintain their rainbow colors "
                        "generated automatically by IMOD.")

    p.add_option("--name", dest = "name", metavar = "STRING",
                 help = "Name for the output objects. If no name is specified, "
                        "the objects will be nameless.")

    p.add_option("--rmbycont", dest = "rmbycont", metavar = "VALUE",
                 help = "Value for automatic removal of objects based on their "
                        "total number of contours. Objects containing a number "
                        "of contours less than or equal to this value will be "
                        "removed. (DEFAULT = 2)")
 
    p.add_option("--output", dest = "path_out", metavar = "PATH",
                 help = "Output path to save to (DEFAULT = Current directory.")

    (opts, args) = p.parse_args()   

    # Set the arguments
    if len(args) != 3:
        usage("Improper number of arguments. See usage below.")
    file_mrc = args[0]
    file_mod = args[1]
    path_seg = args[2]

    # Set the options
    imodautoR = 0
    if opts.pointreduction:
        imodautoR = opts.pointreduction

    imodmeshP = 0
    if opts.passes:
        imodmeshP = opts.passes

    rmbycont = 2
    if opts.rmbycont:
        rmbycont = opts.rmbycont

    # Set and check the output directory
    if opts.path_out:
        path_out = opts.path_out
    else:
        path_out = os.getcwd()
    if not os.path.isdir(path_out):
        usage("The output path {0} does not exist.".format(path_out))

    # Check the validity of the arguments
    if not os.path.isfile(file_mrc):
        usage("The MRC file {0} does not exist.".format(file_mrc))
    if not os.path.isfile(file_mod):
        usage("The model file {0} does not exist.".format(file_mod))

    # Create temporary directory in the output path
    path_tmp = os.path.join(path_out, "tmp")
    if os.path.isdir(path_tmp):
        usage("There is already a folder with the name tmp in the output "
              "path {0}".format(path_out))
    os.makedirs(path_tmp)

    # Get number of slices in MRC file
    cmd = "header -size {0}".format(file_mrc)
    nslices = Popen(cmd.split(), stdout = PIPE)
    nslices = nslices.stdout.read().split()
    nColMrc = int(nslices[0])
    nRowMrc = int(nslices[1])
    nslices = int(nslices[2])

    # Get list of all segmented organelle files
    filesOrg = sorted(glob.glob(os.path.join(path_seg, "*")))

    # Loop
    C = 0
    for i in range(0, nslices):
        file_tmp = os.path.join(path_tmp, "tmp" + str(i).zfill(4))
        cmd = "imodmop -mask 1 -zminmax {0},{0} {1} {2} {3}".format(i, 
              file_mod, file_mrc, file_tmp + ".mrc")
        call(cmd.split())
        cmd = "mrc2tif {0} {1}".format(file_tmp + ".mrc", file_tmp + ".tif")
        call(cmd.split())
        os.remove(file_tmp + ".mrc")

        # Read cell and organelle segmentation images. Resize the cell image
        # to be the same as the organelle image, which is typically larger
        imgOrg = misc.imread(filesOrg[i])
        imgOrg = misc.imresize(imgOrg, [nRowMrc, nColMrc])
        imgCell = misc.imread(file_tmp + ".tif")
        imgCell = misc.imresize(imgCell, [nRowMrc, nColMrc])
        #imgCell = misc.imresize(imgCell, imgOrg.shape)

        # Find the intersection of imgOrg and imgCell. Write this image file
        imgMask = np.logical_and(imgCell, imgOrg)
        imgMask.astype("uint8")
        misc.imsave(file_tmp + ".tif", imgMask)

        # Run imodauto
        cmd = "tif2mrc {0} {1}".format(file_tmp + ".tif", file_tmp + ".mrc")
        call(cmd.split())
        os.remove(file_tmp + ".tif")
        cmd = "imodauto -E 255 -u -R {0} {1} {2}".format(imodautoR,
              file_tmp + ".mrc", file_tmp + ".mod")
        call(cmd.split())
        os.remove(file_tmp + ".mrc") 
        cmd = "imodtrans -tz {0} {1} {1}".format(i, file_tmp + ".mod")
        call(cmd.split())
        cmd = "model2point -object {0} {1}".format(file_tmp + ".mod",
              file_tmp + ".txt")
        call(cmd.split())
        os.remove(file_tmp + ".mod")
        os.remove(file_tmp + ".mod~")

        file_out = os.path.join(path_tmp, "out")        
        if not os.stat(file_tmp + ".txt").st_size == 0:
            with open(file_tmp + ".txt") as handle:
                lastline = (list(handle)[-1])
            handle.close()
            ncont = int(lastline.split()[1])
            with open(file_out + ".txt", "a+") as outfile:
                with open(file_tmp + ".txt", "r+") as infile:
                    for line in infile:
                        lsplit = line.split()
                        newline = "1 {0} {1} {2} {3}\n".format(int(lsplit[1]) + C,
                                  lsplit[2], lsplit[3], lsplit[4])
                        outfile.write(newline)
                #sys.stdout.write(newline)
            C = C + ncont
        os.remove(file_tmp + ".txt")
        
    # Post-processing
    edmodcmd = "edmod.py --rmbycont {0} ".format(rmbycont)
    if opts.color:
        edmodcmd = edmodcmd + "--colorout {0} ".format(opts.color)
    if opts.name:
        edmodcmd = edmodcmd + "--nameout {0} ".format(opts.name)
    edmodcmd = edmodcmd + "{0} {0}".format(file_out + "_sort.mod")  

    cmd = "point2model -image {0} {1} {2}".format(file_mrc, file_out + ".txt",
          file_out + ".mod")
    call(cmd.split())

    cmd = "imodmesh -CTs -P {0} {1} {1}".format(imodmeshP, file_out + ".mod")
    call(cmd.split())

    cmd = "imodsortsurf -s {0} {0}".format(file_out + ".mod", file_out + "_sort.mod")
    call(cmd.split())

    call(edmodcmd.split())

    cmd = "imodmesh -e {0} {0}".format(file_out + "_sort.mod")
    call(cmd.split())

    cmd = "imodmesh -CTs -P {0} {1} {1}".format(imodmeshP, file_out + "_sort.mod")
    call(cmd.split())

    cmd = "imodfillin -e {0} {0}".format(file_out + "_sort.mod")
    call(cmd.split())

    cmd = "imodmesh -e {0} {0}".format(file_out + "_sort.mod")
    call(cmd.split())

    cmd = "imodmesh -CT {0} {0}".format(file_out + "_sort.mod")
    call(cmd.split())  

