classdef PythonRandom < handle
    % CPython random.Random for nonnegative integer seeds. No Python runtime.
    properties (Access = private)
        state
        index = 625
        gaussNext = []
    end
    methods

        function o = PythonRandom(seed)
            assert(isfinite(seed) && seed == fix(seed) && abs(seed) < 2^53, 'Integer seed required');
            n = abs(double(seed));
            key = uint32(mod(n, 2^32));
            if n >= 2^32
                key = [key, uint32(floor(n / 2^32))];
            end
            o.state = zeros(1, 624, 'uint32');
            o.state(1) = uint32(19650218);
            for i = 2:624
                x = bitxor(o.state(i - 1), bitshift(o.state(i - 1), -30));
                o.state(i) = uint32(mod(double(optim.PythonRandom.mul32(x, 1812433253)) + (i - 1), 2^32));
            end
            i = 2;
            j = 1;
            for k = 1:max(624, numel(key))
                x = bitxor(o.state(i - 1), bitshift(o.state(i - 1), -30));
                product = optim.PythonRandom.mul32(x, 1664525);
                o.state(i) = uint32(mod(double(bitxor(o.state(i), product)) + double(key(j)) + (j - 1), 2^32));
                i = i + 1;
                j = j + 1;
                if i > 624
                    o.state(1) = o.state(624);
                    i = 2;
                end
                if j > numel(key)
                    j = 1;
                end
            end
            for k = 1:623
                x = bitxor(o.state(i - 1), bitshift(o.state(i - 1), -30));
                product = optim.PythonRandom.mul32(x, 1566083941);
                o.state(i) = uint32(mod(double(bitxor(o.state(i), product)) - (i - 1), 2^32));
                i = i + 1;
                if i > 624
                    o.state(1) = o.state(624);
                    i = 2;
                end
            end
            o.state(1) = uint32(2147483648);
        end

        function y = word(o)
            if o.index > 624
                for kk = 1:624
                    next = mod(kk, 624) + 1;
                    y = bitor(bitand(o.state(kk), uint32(2147483648)), bitand(o.state(next), uint32(2147483647)));
                    m = mod(kk - 1 + 397, 624) + 1;
                    v = bitxor(o.state(m), bitshift(y, -1));
                    if bitand(y, uint32(1))
                        v = bitxor(v, uint32(2567483615));
                    end
                    o.state(kk) = v;
                end
                o.index = 1;
            end
            y = o.state(o.index);
            o.index = o.index + 1;
            y = bitxor(y, bitshift(y, -11));
            y = bitxor(y, bitand(bitshift(y, 7), uint32(2636928640)));
            y = bitxor(y, bitand(bitshift(y, 15), uint32(4022730752)));
            y = bitxor(y, bitshift(y, -18));
        end

        function v = random(o)
            a = double(bitshift(o.word(), -5));
            b = double(bitshift(o.word(), -6));
            v = (a * 67108864 + b) / 9007199254740992;
        end

        function v = uniform(o, a, b)
            v = a + (b - a) * o.random();
        end

        function v = bits(o, k)
            if k <= 32
                v = double(bitshift(o.word(), k - 32));
            else
                assert(k <= 53);
                v = double(o.word()) + double(bitshift(o.word(), k - 64)) * 2^32;
            end
        end

        function v = randbelow(o, n)
            assert(n >= 1);
            k = floor(log2(n)) + 1;
            v = o.bits(k);
            while v >= n
                v = o.bits(k);
            end
        end

        function v = choice(o, x)
            assert(~isempty(x));
            v = x(o.randbelow(numel(x)) + 1);
        end

        function x = shuffle(o, x)
            for i = numel(x):-1:2
                j = o.randbelow(i) + 1;
                tmp = x(i);
                x(i) = x(j);
                x(j) = tmp;
            end
        end

        function out = sample(o, x, k)
            n = numel(x);
            assert(k >= 0 && k <= n);
            out = x([]);
            out(1:k) = x(1:k);
            setsize = 21;
            if k > 5
                setsize = setsize + 4^ceil(log(k * 3) / log(4));
            end
            if n <= setsize
                pool = x;
                for i = 1:k
                    j = o.randbelow(n - i + 1) + 1;
                    out(i) = pool(j);
                    pool(j) = pool(n - i + 1);
                end
            else
                selected = false(1, n);
                for i = 1:k
                    j = o.randbelow(n) + 1;
                    while selected(j)
                        j = o.randbelow(n) + 1;
                    end
                    selected(j) = true;
                    out(i) = x(j);
                end
            end
        end

        function z = gauss(o, mu, sigma)
            z = o.gaussNext;
            o.gaussNext = [];
            if isempty(z)
                angle = o.random() * 2 * pi;
                radius = sqrt(-2 * log(1 - o.random()));
                z = cos(angle) * radius;
                o.gaussNext = sin(angle) * radius;
            end
            z = mu + z * sigma;
        end

        function v = expovariate(o, lambda)
            v = -log(1 - o.random()) / lambda;
        end

    end
    methods (Static)

        function v = mul32(x, c)
            % Split multiplication avoids losing low bits in IEEE doubles.
            a = double(bitand(uint32(x), uint32(65535)));
            b = double(bitshift(uint32(x), -16));
            v = uint32(mod(a * c + mod(b * c, 65536) * 65536, 2^32));
        end

        function v = roundEven(x)
            f = floor(x);
            v = f + (x - f > 0.5 | (x - f == 0.5 & mod(f, 2) == 1));
        end

        function out = intSetOrder(x)
            % CPython 3.x set table, positive integer IDs, no deletion.
            tab = nan(1, 8);
            used = 0;
            for v = x
                if any(tab == v)
                    continue
                end
                tab = insert(tab, v);
                used = used + 1;
                if used * 5 >= (numel(tab) - 1) * 3
                    n = 8;
                    while n <= used * 4
                        n = n * 2;
                    end
                    old = tab;
                    tab = nan(1, n);
                    for w = old(~isnan(old))
                        tab = insert(tab, w);
                    end
                end
            end
            out = tab(~isnan(tab));

            function a = insert(a, v)
                mask = numel(a) - 1;
                ix = mod(v, numel(a));
                perturb = v;
                while true
                    probes = 0;
                    if ix + 9 <= mask
                        probes = 9;
                    end
                    for probe = 0:probes
                        if isnan(a(ix + probe + 1))
                            a(ix + probe + 1) = v;
                            return
                        end
                    end
                    perturb = floor(perturb / 32);
                    ix = mod(ix * 5 + 1 + perturb, numel(a));
                end
            end

        end

    end
end
