#! /usr/bin/env python

import os
import re
import array
import glob
import sys
import fileinput
import pyimod
import numpy as np
from scipy import misc
from optparse import OptionParser
from subprocess import Popen, call, PIPE
from sys import stderr, exit, argv

def parse_args():
    global p
    p = OptionParser(usage = "%prog [options] file.mrc file.mod path_seg")
    p.add_option("--output",
                 dest = "path_out",
                 metavar = "PATH",
                 help = "Output path to save to (DEFAULT = Current directory.")
    p.add_option("--runImodfillin",
                 action = "store_true",
                 default = False,
                 dest = "runImodfillin",
                 help = "Runs imodfillin to interpolate missing contours in "
                        "file.mod. The number of slices to skip is specified "
                        "by the flag --slicesToSkip. (Default: False)") 
    p.add_option("--slicesToSkip",
                 dest = "slicesToSkip",
                 metavar = "INT",
                 default = 10,
                 help = "Number of slices to skip when interpolating missing "
                        "contours with imodfillin. The value specified here "
                        "is used as input to the -s flag in imodmesh. (Default: "
                        "10.")
    (opts, args) = p.parse_args()
    file_mrc, file_mod, path_seg = check_args(args)
    return opts, file_mrc, file_mod, path_seg

def check_args(args):
    if len(args) is not 3:
        usage('Improper number of arguments.')
    file_mrc = args[0]
    file_mod = args[1]
    path_seg = args[2]
    if not os.path.isfile(file_mrc):
        usage('{0} is not a valid file.'.format(file_mrc))
    if not os.path.isfile(file_mod):
        usage('{0} is not a valid file.'.format(file_mod))
    if not os.path.isdir(path_seg):
        usage('The path {0} does not exist'.format(path_seg))
    return file_mrc, file_mod, path_seg

def get_z_from_ImodContour(cont):
    """
    Returns the Z value of a given ImodContour object. If the contour has more
    than one Z value, returns the mode of the list of all Z values and prints
    a warning message. 
    """
    cont_u = np.unique([int(x) for x in cont.points[2::3]])
    if len(cont_u == 1):
        uq = cont_u[0]
    else:
        uq = max(set(cont_u), key = list.count)
        print 'WARNING: Contour has more than one Z value. Selecting the ' \
            'most common Z value.' 
    return uq

def usage(errstr):
    print ""
    print "ERROR: %s" % errstr
    print ""
    p.print_help()
    print ""
    exit(1)

if __name__ == "__main__":
    opts, file_mrc, file_mod, path_seg = parse_args()

    # Set and check the output directory
    if opts.path_out:
        path_out = opts.path_out
    else:
        path_out = os.getcwd()
    if not os.path.isdir(path_out):
        usage("The output path {0} does not exist.".format(path_out))

    # Create temporary directory in the output path
    path_tmp = os.path.join(path_out, "tmp")
    if os.path.isdir(path_tmp):
        usage("There is already a folder with the name tmp in the output "
              "path {0}".format(path_out))
    os.makedirs(path_tmp)

    # Load cell model file in PyIMOD
    mod = pyimod.ImodModel(file_mod)

    # Run imodfillin, if desired. First, existing mesh data is removed and
    # replaced with a new mesh obtained by skipping across a number of slices,
    # specified by the optional argument --slicesToSkip. Imodfillin is then 
    # run with the -e flag, so that contours are appended to the existing
    # object. 
    if opts.runImodfillin:
        print 'Running imodmesh/imodfillin...'
        print '# Contours before: {0}'.format(mod.Objects[0].nContours)
        mod = pyimod.utils.ImodCmd(mod, 'imodmesh -e')
        mod = pyimod.utils.ImodCmd(mod,
            'imodmesh -CTs -P {0}'.format(opts.slicesToSkip))
        mod = pyimod.utils.ImodCmd(mod, 'imodfillin -e') 
        print '# Contours after: {0}'.format(mod.Objects[0].nContours)

    # Remove small contours and sort contours
    print 'Removing small contours and reordering...'
    print '# Contours before: {0}'.format(mod.Objects[0].nContours)
    mod.removeSmallContours()
    mod.Objects[0].sortContours()
    print '# Contours after: {0}'.format(mod.Objects[0].nContours)

    # Get the minimum and maximum slice values of the cell trace 
    zmin = get_z_from_ImodContour(mod.Objects[0].Contours[0])
    zmax = get_z_from_ImodContour(mod.Objects[0].Contours[-1])
    print 'Z min: {0}'.format(zmin)
    print 'Z max: {0}'.format(zmax)

    # Check that all slices between zmin and zmax have a contour. If not,
    # continue with the process, but print a warning message.
    zprev = zmin
    zlist = []
    for iCont in range(mod.Objects[0].nContours):
        zi = get_z_from_ImodContour(mod.Objects[0].Contours[iCont])
        print 'Contour: {0}, Z: {1}'.format(iCont+1, zi) 
        if iCont and zi != (zprev + 1):
            print 'WARNING: Missing contour'
        zlist.append(zi)
        zprev = zi
    print zlist

    # Get number of slices in MRC file 
    dims = pyimod.mrc.get_dims(file_mrc)
    nColMrc = int(dims[0])
    nRowMrc = int(dims[1])
    nslices = int(dims[2])

    # Get list of all segmented organelle files
    filesOrg = sorted(glob.glob(os.path.join(path_seg , '*')))

    # Loop over all Z values in the cell trace 
    C = 0
    for zi in zlist:
        print 'Processing Z = {0}'.format(zi) 
        # Create a TIF image of the cell mask. This is done by first using
        # imodmop to mask the cell, and then convert it to TIF using mrc2tif. 
        file_tmp = os.path.join(path_tmp, str(zi).zfill(4))
        cmd = 'imodmop -mask 1 -zminmax {0},{0} {1} {2} {3}'.format(zi - 1,
            file_mod, file_mrc, file_tmp + '.mrc')
        call(cmd.split())
        cmd = 'mrc2tif {0} {1}'.format(file_tmp + '.mrc', file_tmp + '.tif')
        call(cmd.split())
        os.remove(file_tmp + '.mrc')

        # Read cell mask image to numpy array
        imgCell = misc.imread(file_tmp + '.tif') 

        # Read the organelle segmentation image to a numpy array 
        imgOrg = misc.imread(filesOrg[zi - 1])
    
        # Resize images, if necessary.
        if (imgCell.shape[0] != nRowMrc) or (imgCell.shape[1] != nColMrc):        
            imgCell = misc.imresize(imgOrg, [nRowMrc, nColMrc])

        if (imgOrg.shape[0] != nRowMrc) or (imgOrg.shape[1] != nColMrc):
            imgOrg = misc.imresize(imgOrg, [nRowMrc, nColMrc])

        # Find the intersection of imgOrg and imgCell. Write this image file.
        imgMask = np.logical_and(imgCell, imgOrg)
        imgMask.astype('uint8')
        misc.imsave(file_tmp + '.tif', imgMask) 

        # Run imodauto
        cmd = 'imodauto -E 255 -u {0} {1}'.format(file_tmp + '.tif',
            file_tmp + '.mod')
        call(cmd.split())
        os.remove(file_tmp + '.tif')

        # Translate the imodauto results in z so they match the correct slice
        cmd = 'imodtrans -tz {0} {1} {1}'.format(zi - 1, file_tmp + '.mod')
        call(cmd.split())
        os.remove(file_tmp + '.mod~')  

        # Convert the translated model to a point listing compatible with
        # model2point
        cmd = 'model2point -object {0} {1}'.format(file_tmp + '.mod',
            file_tmp + '.txt')   
        call(cmd.split())
        os.remove(file_tmp + '.mod')

        # Append to growing file of point listings
        file_out = os.path.join(path_tmp, 'out')
        if not os.stat(file_tmp + '.txt').st_size == 0:
            with open(file_tmp + '.txt') as fid:
                lastline = (list(fid)[-1])
            fid.close()
            ncont = int(lastline.split()[1])
            with open(file_out + '.txt', 'a+') as outfile:
                with open(file_tmp + '.txt', 'r+') as infile:
                    for line in infile:
                        lsplit = line.split()
                        newline = '1 {0} {1} {2} {3}\n'.format(int(lsplit[1]) + C,
                            lsplit[2], lsplit[3], lsplit[4])
                        outfile.write(newline)
            C = C + ncont    
        os.remove(file_tmp + '.txt') 

    # Convert point listing to final model file
    cmd = 'point2model -image {0} {1} {2}'.format(file_mrc, file_out + '.txt',
        file_out + '.mod')


 
