# Locate the workbook to be analysed

Finds the single Excel workbook held in a folder, by default `inputs/`.
This is the entry point for users who place one workbook in that folder
and do not want to type a file path.

## Usage

``` r
find_workbook(dir = "inputs")
```

## Arguments

- dir:

  Folder to search. Defaults to `"inputs"`, relative to the working
  directory.

## Value

A single file path.

## Details

Temporary lock files that Excel creates while a workbook is open (names
beginning `~$`) are ignored, as are files beginning with a dot.

## Examples

``` r
if (FALSE) { # \dontrun{
find_workbook()
} # }
```
