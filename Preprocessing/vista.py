#!/usr/bin/env python
# -*- coding : utf-8 -*-
"""
Calculate/process the aMWF from ViSTa data.
Adapted by Hunter G. Moss,PhD to Python3 from MATLAB code 
provided by Oh et al. (2013) MATLAB code 
12/06/2023
"""
import os
import os.path as op
import nibabel as nib
import numpy as np


def vistaCalc(input, reference, output):
    """Calculates the apparent myelin water fraction (aMWF) from ViSTa data

        Note: This code module was adapted from a MATLAB script provided by
        Jungho Li's lab in South Korea. For more detailed information, see:

        Oh et al. (2013) - Direct Visualization of Short Transverse Relaxation Time Component (ViSTa)

    Args:

        input (str): filePath/fileName to raw ViSTa (note: must be .nii/.nii.gz)
        reference (str): filePath/fileName to raw ViSTa reference for normalization (note: must be .nii/.nii.gz)
        output (str): filePath of parent directory to store processed ViSTa image

    """
    # Get just NIFTI filename + extension
    (path, ifile) = os.path.split(input)
    (path, rfile) = os.path.split(reference)

    # Check if the file(s) exists...
    if not os.path.exists(input):
        raise OSError("Raw ViSTa image {} not found".format(ifile))
    if not os.path.exists(reference):
        raise OSError("Reference ViSTa image {} not found".format(rfile))

    # Load in the raw and reference ViSTa images
    hdr = nib.load(input)
    inData = np.array(hdr.dataobj)

    hdr = nib.load(reference)
    refData = np.array(hdr.dataobj)

    """
    
        ==============================
        !!!!        WARNING       !!!!
        ==============================
        DO NOT MODIFY BELOW THIS POINT
        ==============================
                
    """
    echo_gre = 5.5
    echo_vista = 5.5
    flip_gre = 28
    tr_gre = 100
    mask = refData > 100

    sf_gre_T1 = (1 - np.exp(-tr_gre / 800)) * np.sin(flip_gre * (np.pi / 180)) / (1 - np.exp(-tr_gre / 800)* np.cos(flip_gre * (np.pi / 180)))
    sf_gre_T2s = np.exp(-echo_gre / 40)
    sf_vista_T1 = 0.69
    sf_vista_T2s = np.exp(-echo_vista / 10)
    sf = (sf_gre_T1 * sf_gre_T2s) / (sf_vista_T1 * sf_vista_T2s)

    vista = (inData / refData) * sf * mask

    intODF_Img = nib.Nifti1Image(vista, hdr.affine, hdr.header)
    intODF_Img.to_filename(op.join(output, "vista.nii"))


if __name__ == "__main__":
    import sys

    vistaCalc(sys.argv[1], sys.argv[2], sys.argv[3])
