# Read one analysis sheet

Reads the concentration-response data from a single sheet, together with
everything needed to fit it: the response variable, the number of trials
where the response is a count, and the family.

## Usage

``` r
read_analysis_sheet(path, sheet)
```

## Arguments

- path:

  Path to the workbook.

- sheet:

  Sheet name.

## Value

An object of class `analysis_sheet`: a list holding the data frame
(`data`), the sheet name, the variable names, the family call and the
column headings read from the sheet.

## Examples

``` r
if (FALSE) { # \dontrun{
read_analysis_sheet(find_workbook(), "Copper Ref (4)")
} # }
```
