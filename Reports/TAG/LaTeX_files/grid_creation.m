clear
close all
clc

[x,y,z] = textread('edges.txt','%d %d %d');

for i=1:length(x)
    for j=1:length(y)
        if(x(i)==y(j) && x(j)==y(i))
            x(j)=-1;
            y(j)=-1;
        end
    end
end
x=x(x~=-1)+1;
y=y(y~=-1)+1;
G = graph(x,y);

figure, plot(G), axis off