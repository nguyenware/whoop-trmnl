import Foundation

/// The Cole LMS method plus the normal-distribution helpers needed to turn
/// z-scores into exact percentiles and back.
enum LMSMath {

    /// Z-score of `value` given LMS parameters (Cole, 1990).
    static func zScore(value: Double, l: Double, m: Double, s: Double) -> Double {
        if abs(l) < 1e-9 {
            return log(value / m) / s
        }
        return (pow(value / m, l) - 1) / (l * s)
    }

    /// Inverse of `zScore`: the measurement value at a given z.
    static func value(z: Double, l: Double, m: Double, s: Double) -> Double {
        if abs(l) < 1e-9 {
            return m * exp(s * z)
        }
        return m * pow(1 + l * s * z, 1 / l)
    }

    /// Standard normal cumulative distribution function.
    static func normalCDF(_ z: Double) -> Double {
        0.5 * erfc(-z / 2.0.squareRoot())
    }

    /// Standard normal quantile (inverse CDF) for p in (0, 1).
    /// Acklam's algorithm; absolute error < 1.15e-9, ample for percentile curves.
    static func normalQuantile(_ p: Double) -> Double {
        precondition(p > 0 && p < 1, "p must be in (0, 1)")

        let a: [Double] = [-3.969683028665376e+01, 2.209460984245205e+02,
                           -2.759285104469687e+02, 1.383577518672690e+02,
                           -3.066479806614716e+01, 2.506628277459239e+00]
        let b: [Double] = [-5.447609879822406e+01, 1.615858368580409e+02,
                           -1.556989798598866e+02, 6.680131188771972e+01,
                           -1.328068155288572e+01]
        let c: [Double] = [-7.784894002430293e-03, -3.223964580411365e-01,
                           -2.400758277161838e+00, -2.549732539343734e+00,
                           4.374664141464968e+00, 2.938163982698783e+00]
        let d: [Double] = [7.784695709041462e-03, 3.224671290700398e-01,
                           2.445134137142996e+00, 3.754408661907416e+00]

        let pLow = 0.02425
        let pHigh = 1 - pLow

        if p < pLow {
            let q = sqrt(-2 * log(p))
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                   ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > pHigh {
            let q = sqrt(-2 * log(1 - p))
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
               (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }

    /// Human-readable percentile string, clamped at the extremes
    /// (an exact "99.99998th percentile" is noise, not signal).
    static func percentileLabel(_ percentile: Double) -> String {
        if percentile < 0.1 { return "<0.1%" }
        if percentile > 99.9 { return ">99.9%" }
        if percentile < 1 || percentile > 99 {
            return String(format: "%.1f%%", percentile)
        }
        return String(format: "%.0f%%", percentile)
    }
}
