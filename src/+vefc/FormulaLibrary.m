classdef FormulaLibrary
    methods (Static)

        function v = dbmToWatt(x)
            v = 10.^((double(x) - 30) / 10);
        end

        function v = mhzToHz(x)
            v = double(x) * 1e6;
        end

        function v = ghzToHz(x)
            v = double(x) * 1e9;
        end

        function v = distance3d(a, za, b, zb)
            d = a - b;
            v = (d(1) * d(1) + d(2) * d(2) + (za - zb) * (za - zb))^0.5;
        end

        function v = distance2d(a, b)
            d = a - b;
            v = (d(1) * d(1) + d(2) * d(2))^0.5;
        end

        function v = computeTime(c, f)
            assert(c >= 0 && f > 0);
            v = c / f;
        end

        function v = localEnergy(k, c, f)
            v = k * f^2 * c;
        end

        function f = assignedCpuFrequency(a, e, b, k, t, m)
            assert(all(isfinite([a e b k t m])) && e > 0 && k > 0 && t > 0 && m > 0);
            if b <= 0
                f = m;
            else
                f = min(m, (a * e / (2 * b * k * t))^(1 / 3));
            end
        end

        function t = referenceTime(l, d)
            assert(l > 0 && d > 0);
            t = min(l, d);
        end

        function [a, b] = articleWeights(d)
            assert(d > 0);
            a = 0.01 / d + 0.6;
            b = 1 - a;
            assert(a >= 0 && a <= 1 && b >= 0);
        end

        function v = v2iPathLoss(d)
            v = 128.1 + 37.6 * log10(max(d, 1) / 1000);
        end

        function v = v2vPathLoss(d)
            v = 22.7 * log10(max(d, 10)) + 41 + 20 * log10(2 / 5);
        end

        function v = channelGain(loss, shadow, ray, gt, gr)
            v = max(10^((gt + gr - loss) / 10) * 10^(-shadow / 10) * max(ray, 1e-12), 1e-30);
        end

        function r = uplinkRate(B, share, p, h, noise)
            r = B / max(share, 1) * log2(1 + p * h / noise);
        end

        function t = transmissionTime(b, r)
            assert(r > 0);
            t = b / r;
        end

        function e = transmissionEnergy(p, t)
            e = p * t;
        end

        function y = powerAuxiliary(p, a, t, b, e, ~, ~, h, d)
            % Equation (32), not the objective itself.
            y = (b / e) * log2(1 + p * h / d) - (a / t + (b / e) * p) * (h / (log(2) * (d + p * h)));
        end

        function p = optimizeTransmitPower(a, t, b, e, bits, B, h, d, pmax)
            y = @(p)vefc.FormulaLibrary.powerAuxiliary(p, a, t, b, e, bits, B, h, d);
            l = 0;
            u = pmax;
            if y(u) <= 0
                p = u;
                return
            end
            while u - l > 1e-6
                m = (l + u) * 0.5;
                if y(m) <= 0
                    l = m;
                else
                    u = m;
                end
            end
            p = (l + u) * 0.5;
        end

        function q = offloadingEfficiency(a, b, t, e, to, eo)
            assert(t > 0 && e > 0);
            q = a * ((t - to) / t) + b * ((e - eo) / e);
        end

        function q = paperEfficiency(a, b, t, e, to, eo)
            % paper_model.offloading_efficiency multiplies before dividing. Keep this
            % separate from the ratio-first score used to select greedy task providers.
            assert(t > 0 && e > 0);
            q = a * (t - to) / t + b * (e - eo) / e;
        end

        function s = levySigma(l)
            s = (gamma(1 + l) * sin(pi * l / 2) / (gamma((1 + l) / 2) * l * 2^((l - 1) / 2)))^(1 / l);
        end

        function v = levyNormalized(l, r)
            u = r.gauss(0, vefc.FormulaLibrary.levySigma(l));
            v = r.gauss(0, 1);
            z = abs(u / (abs(v)^(1 / l)));
            v = z / (1 + z);
        end

        function v = sumOrdered(x)
            v = 0;
            for a = x(:)'
                v = v + a;
            end
        end

        function v = pythonSum(x)
            % Match CPython 3.12/3.13 sum(float): ordered Neumaier compensation.
            % Explicit += loops in the source library still use sumOrdered instead.
            hi = 0;
            lo = 0;
            for a = x(:)'
                t = hi + a;
                if abs(hi) >= abs(a)
                    lo = lo + ((hi - t) + a);
                else
                    lo = lo + ((a - t) + hi);
                end
                hi = t;
            end
            v = hi;
            if lo ~= 0 && isfinite(lo)
                v = hi + lo;
            end
        end

    end
end
