module foo2
using Mimi

@deftimestep bar function run(v,p,i,t)
    v.a = p.b[3]

    v.a[4,2] = p.c
end

end