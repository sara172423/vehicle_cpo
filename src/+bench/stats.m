function st = stats(values)
    v = sort(double(values(:)'));
    n = numel(v);
    names = {'mean', 'std', 'min', 'max', 'median', 'q1', 'q3', 'iqr', 'ci95'};
    st = cell2struct(num2cell(zeros(1, 9)), names, 2);
    if n == 0
        return
    end
    st.mean = mean(v);
    if n > 1
        st.std = std(v, 0);
    end
    st.min = v(1);
    st.max = v(end);
    st.median = median(v);
    st.q1 = percentile(.25);
    st.q3 = percentile(.75);
    st.iqr = st.q3 - st.q1;
    st.ci95 = 1.96 * st.std / sqrt(n);

    function z = percentile(p)
        position = p * (n - 1);
        lo = floor(position);
        hi = ceil(position);
        w = position - lo;
        z = v(lo + 1) * (1 - w) + v(hi + 1) * w;
    end

end
